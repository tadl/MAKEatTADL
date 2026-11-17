require "nokogiri"
require "pathname"
require "stringio"
require "zip"

# A bounded, read-only illustration of the actual mesh, rather than a print preview.
# 3MF materials, textures, beam lattices, and mixed-unit assemblies are unsupported.
class ModelThumbnail
  MAX_SOURCE_BYTES = 20 * 1024 * 1024
  MAX_XML_BYTES = 20 * 1024 * 1024
  MAX_ZIP_ENTRIES = 256
  MAX_MODEL_PARTS = 16
  MAX_VERTICES = 100_000
  MAX_EXPANDED_VERTICES = 200_000
  MAX_SOURCE_TRIANGLES = 400_000
  MAX_TRIANGLES = 20_000
  MAX_COMPONENTS = 512
  MAX_COMPONENT_DEPTH = 12
  MAX_COORDINATE = 1_000_000_000
  CORE_NAMESPACE = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
  NAMESPACES = { "m" => CORE_NAMESPACE }.freeze
  IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0].freeze
  BASE_COLOR = [73, 104, 142].freeze

  class InvalidModel < StandardError; end

  def self.placeholder
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 200" role="img" aria-label="Model preview unavailable">
        <rect width="320" height="200" fill="#f1f5f9"/>
        <ellipse cx="160" cy="162" rx="65" ry="9" fill="#e2e8f0"/>
        <g fill="none" stroke="#94a3b8" stroke-width="2" stroke-linejoin="round">
          <path d="m160 48 52 30v60l-52 30-52-30V78z M108 78l52 30 52-30 M160 108v60"/>
        </g>
      </svg>
    SVG
  end

  def initialize(blob)
    @blob = blob
  end

  def svg
    extension = File.extname(@blob.filename.to_s).downcase if @blob
    raise InvalidModel unless %w[.stl .3mf].include?(extension)
    bytes = download_source
    triangles = case extension
    when ".stl" then stl_triangles(bytes)
    when ".3mf" then three_mf_triangles(bytes)
    else raise InvalidModel
    end
    render_triangles(triangles)
  rescue InvalidModel, Zip::Error, Zlib::Error, Nokogiri::XML::SyntaxError,
         ArgumentError, TypeError, EOFError, Encoding::CompatibilityError,
         ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError
    self.class.placeholder
  end

  private

  def download_source
    raise InvalidModel unless @blob && @blob.byte_size.positive? && @blob.byte_size <= MAX_SOURCE_BYTES

    bytes = "".b
    @blob.download do |chunk|
      raise InvalidModel if bytes.bytesize + chunk.bytesize > MAX_SOURCE_BYTES
      bytes << chunk
    end
    raise InvalidModel if bytes.empty?
    bytes
  end

  def stl_triangles(bytes)
    count = bytes.byteslice(80, 4)&.unpack1("V") if bytes.bytesize >= 84
    if count && bytes.bytesize == 84 + count * 50
      raise InvalidModel unless count.positive? && count <= MAX_SOURCE_TRIANGLES
      stride = (count.to_f / MAX_TRIANGLES).ceil
      return (0...count).step(stride).map do |index|
        bytes.byteslice(84 + index * 50 + 12, 36).unpack("e9").each_slice(3).map do |vertex|
          vertex.map { |value| finite_coordinate(value) }
        end
      end
    end
    ascii_stl_triangles(bytes)
  end

  def ascii_stl_triangles(bytes)
    raise InvalidModel unless bytes.ascii_only? && bytes.lstrip.start_with?("solid")
    count = bytes.each_line.count { |line| line.strip == "endfacet" }
    raise InvalidModel unless count.positive? && count <= MAX_SOURCE_TRIANGLES
    stride = (count.to_f / MAX_TRIANGLES).ceil
    triangles = []
    vertices = nil
    facet_index = 0
    finished = false
    bytes.each_line do |line|
      text = line.strip
      case text
      when /\Afacet\s+normal\s+\S+\s+\S+\s+\S+\z/
        raise InvalidModel if vertices || finished
        vertices = []
      when /\Avertex\s+(\S+)\s+(\S+)\s+(\S+)\z/
        raise InvalidModel unless vertices && vertices.length < 3
        coordinates = [Regexp.last_match(1), Regexp.last_match(2), Regexp.last_match(3)]
        vertices << coordinates.map { |value| finite_coordinate(value) }
      when "endfacet"
        raise InvalidModel unless vertices&.length == 3
        triangles << vertices if (facet_index % stride).zero?
        facet_index += 1
        vertices = nil
      when /\Aendsolid(?:\s.*)?\z/
        raise InvalidModel if vertices
        finished = true
      when "", "outer loop", "endloop", /\Asolid(?:\s.*)?\z/
        # STL labels and supplied normals never become SVG markup.
      else
        raise InvalidModel
      end
    end
    raise InvalidModel unless finished && vertices.nil? && facet_index == count
    triangles
  end

  def three_mf_triangles(bytes)
    # Count using Rubyzip's directory reader before allocating all entry objects.
    count = Zip::CentralDirectory.new.count_entries(StringIO.new(bytes))
    raise InvalidModel unless count.positive? && count <= MAX_ZIP_ENTRIES
    @xml_bytes = 0
    @part_cache = {}
    @xml_cache = {}
    @vertex_count = 0
    @expanded_vertices = 0
    @component_count = 0
    @triangles = []
    Zip::File.open_buffer(StringIO.new(bytes, "rb")) do |archive|
      @entries = archive.entries.to_h do |entry|
        [part_path(entry.name), entry]
      end
      raise InvalidModel unless @entries.length == count
      part = main_part
      document = load_part(part)
      items = document.fetch(:document).xpath("/m:model/m:build/m:item", NAMESPACES)
      raise InvalidModel if items.empty? || items.length > MAX_COMPONENTS
      items.each do |item|
        expand_object(part, resource_id(item["objectid"]), [matrix(item["transform"])], [])
        break if @triangles.length >= MAX_TRIANGLES
      end
    end
    @triangles
  end

  def main_part
    if @entries.key?("_rels/.rels")
      relationships = parse_xml(read_entry("_rels/.rels"))
      relationship = relationships.at_xpath("//*[local-name()='Relationship'][@Type='http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel']")
      if relationship
        raise InvalidModel if relationship["TargetMode"] == "External"
        return part_path(relationship["Target"])
      end
    end
    @entries.keys.find { |name| name.casecmp?("3D/3dmodel.model") } ||
      @entries.keys.find { |name| name.end_with?(".model") } || raise(InvalidModel)
  end

  def load_part(path)
    return @part_cache[path] if @part_cache.key?(path)
    raise InvalidModel if @part_cache.length >= MAX_MODEL_PARTS
    document = parse_xml(read_entry(path))
    root = document.root
    raise InvalidModel unless root&.name == "model" && root.namespace&.href == CORE_NAMESPACE
    unit = root["unit"].presence || "millimeter"
    @root_unit ||= unit
    raise InvalidModel unless unit == @root_unit
    nodes = document.xpath("/m:model/m:resources/m:object", NAMESPACES)
    raise InvalidModel if nodes.length > MAX_COMPONENTS
    objects = nodes.to_h { |object| [resource_id(object["id"]), object] }
    raise InvalidModel unless objects.length == nodes.length
    @part_cache[path] = { document: document, objects: objects, meshes: {} }
  end

  def read_entry(path)
    return @xml_cache[path] if @xml_cache.key?(path)
    entry = @entries[path]
    remaining = MAX_XML_BYTES - @xml_bytes
    raise InvalidModel unless entry && entry.ftype == :file && !entry.encrypted? && entry.size.positive? && entry.size <= remaining
    text = entry.get_input_stream { |input| input.read(remaining + 1) }
    raise InvalidModel unless text && text.bytesize <= remaining && text.bytesize == entry.size
    @xml_bytes += text.bytesize
    @xml_cache[path] = text
  end

  def parse_xml(text)
    raise InvalidModel if text.match?(/<!\s*(?:DOCTYPE|ENTITY)\b/i)
    document = Nokogiri::XML(text) { |config| config.strict.nonet }
    raise InvalidModel if document.internal_subset || document.external_subset
    document
  end

  def expand_object(path, id, transforms, ancestors)
    @component_count += 1
    key = [path, id]
    raise InvalidModel if @component_count > MAX_COMPONENTS || ancestors.length >= MAX_COMPONENT_DEPTH || ancestors.include?(key)
    part = load_part(path)
    object = part.fetch(:objects)[id] || raise(InvalidModel)
    mesh = object.at_xpath("m:mesh", NAMESPACES)
    components = object.xpath("m:components/m:component", NAMESPACES)
    raise InvalidModel if mesh && components.any?
    if mesh
      vertices, faces = part.fetch(:meshes)[id] ||= mesh_data(mesh)
      @expanded_vertices += vertices.length
      raise InvalidModel if @expanded_vertices > MAX_EXPANDED_VERTICES
      transformed = vertices.map { |vertex| transform_point(vertex, transforms) }
      faces.each do |face|
        @triangles << face.map { |index| transformed.fetch(index) }
        break if @triangles.length >= MAX_TRIANGLES
      end
    else
      raise InvalidModel if components.empty? || components.length > MAX_COMPONENTS
      components.each do |component|
        reference = component.attribute_nodes.find { |attribute| attribute.name == "path" }&.value
        child_path = reference ? part_path(reference, base: path) : path
        expand_object(child_path, resource_id(component["objectid"]), transforms + [matrix(component["transform"])], ancestors + [key])
        break if @triangles.length >= MAX_TRIANGLES
      end
    end
  end

  def mesh_data(mesh)
    vertex_nodes = mesh.xpath("m:vertices/m:vertex", NAMESPACES)
    @vertex_count += vertex_nodes.length
    raise InvalidModel if vertex_nodes.empty? || @vertex_count > MAX_VERTICES
    vertices = vertex_nodes.map { |vertex| %w[x y z].map { |axis| finite_coordinate(vertex[axis]) } }
    triangle_nodes = mesh.xpath("m:triangles/m:triangle", NAMESPACES)
    raise InvalidModel if triangle_nodes.empty? || triangle_nodes.length > MAX_SOURCE_TRIANGLES
    stride = (triangle_nodes.length.to_f / MAX_TRIANGLES).ceil
    faces = triangle_nodes.each_with_index.filter_map do |triangle, index|
      next unless (index % stride).zero?
      %w[v1 v2 v3].map do |attribute|
        value = resource_id(triangle[attribute], zero: true)
        raise InvalidModel if value >= vertices.length
        value
      end
    end
    [vertices, faces]
  end

  def part_path(value, base: "")
    raise InvalidModel unless value.is_a?(String) && value.present? && value.bytesize <= 1024 && !value.match?(/[\\:\x00]/)
    path = if value.start_with?("/")
      value.delete_prefix("/")
    else
      File.join(File.dirname(base), value)
    end
    path = Pathname.new(path).cleanpath.to_s
    raise InvalidModel if path == "." || path == ".." || path.start_with?("../", "/")
    path
  end

  def resource_id(value, zero: false)
    raise InvalidModel unless value.is_a?(String) && value.match?(/\A\d{1,10}\z/)
    number = Integer(value, 10)
    raise InvalidModel if number < (zero ? 0 : 1) || number > 2_147_483_647
    number
  end

  def matrix(value)
    return IDENTITY if value.blank?
    raise InvalidModel if value.bytesize > 2048
    values = value.split
    raise InvalidModel unless values.length == 12
    values.map { |number| finite_coordinate(number) }
  end

  def transform_point(vertex, transforms)
    transforms.reverse_each.reduce(vertex) do |(x, y, z), transform|
      3.times.map do |axis|
        finite_coordinate(x * transform[axis] + y * transform[3 + axis] + z * transform[6 + axis] + transform[9 + axis])
      end
    end
  end

  def finite_coordinate(value)
    raise InvalidModel if value.is_a?(String) && value.bytesize > 128
    number = Float(value)
    raise InvalidModel unless number.finite? && number.abs <= MAX_COORDINATE
    number
  end

  def render_triangles(triangles)
    raise InvalidModel if triangles.empty?
    vertices = triangles.flatten(1)
    bounds = 3.times.map { |axis| vertices.map { |vertex| vertex[axis] }.minmax }
    size = bounds.map { |low, high| high - low }.max
    raise InvalidModel unless size.positive? && size.finite?
    centers = bounds.map { |low, high| (low + high) / 2.0 }
    faces = triangles.filter_map do |triangle|
      points = triangle.map { |vertex| 3.times.map { |axis| (vertex[axis] - centers[axis]) / size } }
      normal = surface_normal(points)
      next unless normal
      projected = points.map { |x, y, z| [(x - y) * Math.sqrt(3) / 2, (x + y) / 2 - z] }
      area = (projected[1][0] - projected[0][0]) * (projected[2][1] - projected[0][1]) -
        (projected[1][1] - projected[0][1]) * (projected[2][0] - projected[0][0])
      next if area.abs < 1e-12
      { points: projected, depth: points.sum(&:sum), normal: normal }
    end
    raise InvalidModel if faces.empty?
    # The projection looks toward the origin from [1, 1, 1]. Back faces on thin
    # closed meshes can otherwise overpaint the front when centroids overlap.
    front_faces = faces.select { |face| face[:normal].sum > 1e-12 }
    faces = front_faces if front_faces.any?
    projected = faces.flat_map { |face| face[:points] }
    left, right = projected.map(&:first).minmax
    top, bottom = projected.map(&:last).minmax
    scale = [256 / (right - left), 144 / (bottom - top)].min
    polygons = faces.sort_by { |face| face[:depth] }.map do |face|
      points = face[:points].map { |x, y| "#{format('%.2f', 160 + (x - (left + right) / 2) * scale)},#{format('%.2f', 96 + (y - (top + bottom) / 2) * scale)}" }.join(" ")
      light = [face[:normal].zip([-0.3, 0.5, 0.81]).sum { |normal, direction| normal * direction }, 0].max
      shade = 0.52 + 0.48 * light
      color = "#" + BASE_COLOR.map { |channel| format("%02x", (channel * shade + 230 * (1 - shade) * 0.15).round.clamp(0, 255)) }.join
      %(<polygon points="#{points}" fill="#{color}" stroke="#{color}" stroke-width="0.4" stroke-linejoin="round"/> )
    end.join
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 200" role="img" aria-label="3D model thumbnail">
        <rect width="320" height="200" fill="#f1f5f9"/>
        <ellipse cx="160" cy="176" rx="88" ry="10" fill="#dce4eb"/>
        #{polygons}
      </svg>
    SVG
  end

  def surface_normal(points)
    u = 3.times.map { |axis| points[1][axis] - points[0][axis] }
    v = 3.times.map { |axis| points[2][axis] - points[0][axis] }
    cross = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
    length = Math.sqrt(cross.sum { |coordinate| coordinate**2 })
    cross.map { |coordinate| coordinate / length } if length > 1e-12
  end
end
