require "test_helper"
require_relative "../../lib/development/demo_assets"

class ModelThumbnailTest < ActiveSupport::TestCase
  Blob = Struct.new(:filename, :bytes, :declared_size, :downloaded) do
    def byte_size
      declared_size || bytes.bytesize
    end

    def download
      self.downloaded = true
      yield bytes
    end
  end

  test "ASCII STL renders actual shaded geometry without filenames or source markup" do
    source = Development::DemoAssets.stl.sub("demo_cube", "<script>source-label</script>")
    blob = Blob.new("<script>filename</script>.stl", source)

    svg = ModelThumbnail.new(blob).svg

    assert_geometry svg
    assert_not_includes svg, "script"
    assert_not_includes svg, "source-label"
    assert_not_includes svg, "filename"
    assert_operator document(svg).css("polygon").map { |polygon| polygon["fill"] }.uniq.length, :>=, 2
  end

  test "binary STL with a solid header is detected by its binary structure" do
    svg = ModelThumbnail.new(Blob.new("binary.stl", binary_stl)).svg

    assert_geometry svg
    assert_equal 6, document(svg).css("polygon").length
  end

  test "3MF ZIP mesh produces a thumbnail" do
    svg = ModelThumbnail.new(Blob.new("cube.3mf", Development::DemoAssets.three_mf)).svg

    assert_geometry svg
    assert_equal 6, document(svg).css("polygon").length
  end

  test "3MF assemblies follow bounded cross-part references and affine transforms" do
    main = <<~XML
      <model xmlns="#{ModelThumbnail::CORE_NAMESPACE}" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
        <resources><object id="2"><components>
          <component objectid="1" p:path="/3D/Objects/part.model"/>
          <component objectid="1" p:path="/3D/Objects/part.model" transform="1 0 0 0 1 0 0 0 1 30 0 0"/>
        </components></object></resources>
        <build><item objectid="2"/></build>
      </model>
    XML
    archive = zip_model(main, "3D/Objects/part.model" => cube_xml)

    svg = ModelThumbnail.new(Blob.new("assembly.3mf", archive)).svg

    assert_geometry svg
    assert_equal 12, document(svg).css("polygon").length
    assert_operator document(svg).css("polygon").flat_map { |polygon| polygon["points"].split }.uniq.length, :>, 8
  end

  test "unsupported malformed empty and degenerate models use the safe placeholder" do
    degenerate = Development::DemoAssets.stl.gsub(/vertex [^\n]+/, "vertex 0 0 0")
    [Blob.new("unsupported.obj", "synthetic model"), Blob.new("bad.stl", "not a model"),
     Blob.new("empty.stl", ""), Blob.new("degenerate.stl", degenerate),
     Blob.new("bad.3mf", "not a ZIP"), Blob.new("truncated.stl", binary_stl.byteslice(0, 100))].each do |blob|
      assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(blob).svg
    end
  end

  test "back-facing triangles cannot overpaint the same front-facing surface" do
    front = [[0, 0, 0], [1, 0, 0], [0, 1, 0]]
    front_svg = ModelThumbnail.new(Blob.new("front.stl", ascii_triangles([front]))).svg
    mixed_svg = ModelThumbnail.new(Blob.new("both.stl", ascii_triangles([front, front.reverse]))).svg

    assert_geometry mixed_svg
    assert_equal 1, document(mixed_svg).css("polygon").length
    assert_equal front_svg, mixed_svg
  end

  test "a reversed open plane still renders when no face points toward the camera" do
    back = [[0, 0, 0], [0, 1, 0], [1, 0, 0]]

    svg = ModelThumbnail.new(Blob.new("reversed.stl", ascii_triangles([back]))).svg

    assert_geometry svg
    assert_equal 1, document(svg).css("polygon").length
  end

  test "non-finite or excessive coordinates never become SVG points" do
    ["NaN", "Infinity", "1e9999", "100000000000000000000"].each do |coordinate|
      source = Development::DemoAssets.stl.sub(/vertex\s+\S+/, "vertex #{coordinate}")
      assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("invalid.stl", source)).svg
    end
    source = binary_stl
    source[96, 4] = [Float::INFINITY].pack("e")
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("invalid-binary.stl", source)).svg
  end

  test "source limits reject declared and actual oversized content" do
    blob = Blob.new("oversized.stl", Development::DemoAssets.stl, ModelThumbnail::MAX_SOURCE_BYTES + 1)
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(blob).svg
    assert_not blob.downloaded

    blob = Blob.new("wrong-size.stl", "x" * (ModelThumbnail::MAX_SOURCE_BYTES + 1), 1)
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(blob).svg
  end

  test "3MF rejects oversized decompressed model entries and excessive ZIP entries" do
    oversized = cube_xml + " " * ModelThumbnail::MAX_XML_BYTES
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("oversized.3mf", zip_model(oversized))).svg

    extras = (0...ModelThumbnail::MAX_ZIP_ENTRIES).to_h { |index| ["metadata/#{index}.txt", ""] }
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("many-entries.3mf", zip_model(cube_xml, extras))).svg
  end

  test "3MF rejects DTD entities invalid references and cyclic assemblies" do
    doctype = '<!DOCTYPE model [<!ENTITY sample SYSTEM "file:///nonexistent-model-thumbnail-test">]>'
    xml = cube_xml.sub(/(<model\b)/, "#{doctype}\\1")
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("entity.3mf", zip_model(xml))).svg

    xml = cube_xml.sub('v1="0"', 'v1="999999"')
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("bad-index.3mf", zip_model(xml))).svg

    xml = <<~XML
      <model xmlns="#{ModelThumbnail::CORE_NAMESPACE}">
        <resources><object id="1"><components><component objectid="1"/></components></object></resources>
        <build><item objectid="1"/></build>
      </model>
    XML
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("cycle.3mf", zip_model(xml))).svg
  end

  test "3MF rejects model-part paths outside the archive and malformed transforms" do
    xml = <<~XML
      <model xmlns="#{ModelThumbnail::CORE_NAMESPACE}" xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06">
        <resources><object id="1"><components><component objectid="2" p:path="../../outside.model"/></components></object></resources>
        <build><item objectid="1"/></build>
      </model>
    XML
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("path.3mf", zip_model(xml))).svg

    xml = cube_xml.sub('<item objectid="1"', '<item transform="1 2 3" objectid="1"')
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("transform.3mf", zip_model(xml))).svg
  end

  test "3MF vertex count and rendered triangle work are bounded" do
    excess_vertices = '<vertex x="0" y="0" z="0"/>' * (ModelThumbnail::MAX_VERTICES + 1)
    xml = cube_xml.sub("</vertices>", "#{excess_vertices}</vertices>")
    assert_equal ModelThumbnail.placeholder, ModelThumbnail.new(Blob.new("vertices.3mf", zip_model(xml))).svg

    count = ModelThumbnail::MAX_TRIANGLES + 1
    facet = binary_stl.byteslice(84, 50)
    bytes = "sampled binary".ljust(80, "\0") + [count].pack("V") + facet * count
    svg = ModelThumbnail.new(Blob.new("sampled.stl", bytes)).svg
    assert_geometry svg
    assert_operator document(svg).css("polygon").length, :<=, ModelThumbnail::MAX_TRIANGLES
  end

  private

  def assert_geometry(svg)
    assert_not_equal ModelThumbnail.placeholder, svg
    assert_operator document(svg).css("polygon").length, :>, 0
    refute_match(/NaN|Infinity|<script|(?:href|onload)=/, svg)
    coordinates = document(svg).css("polygon").flat_map { |polygon| polygon["points"].split(/[ ,]/) }
    assert coordinates.all? { |coordinate| Float(coordinate).finite? }
  end

  def document(svg)
    Nokogiri::XML(svg) { |config| config.strict.nonet }
  end

  def binary_stl
    facets = Development::DemoAssets::TRIANGLES.map do |triangle|
      coordinates = triangle.flat_map { |index| Development::DemoAssets::VERTICES[index].map { |value| value * 20.0 } }
      ([0.0, 0.0, 0.0] + coordinates).pack("e12") + [0].pack("v")
    end
    "solid binary cube".ljust(80, "\0") + [facets.length].pack("V") + facets.join
  end

  def ascii_triangles(triangles)
    facets = triangles.map do |triangle|
      points = triangle.map { |point| "vertex #{point.join(' ')}" }.join("\n")
      "facet normal 0 0 0\nouter loop\n#{points}\nendloop\nendfacet"
    end.join("\n")
    "solid thumbnail_test\n#{facets}\nendsolid thumbnail_test\n"
  end

  def cube_xml
    xml = nil
    Zip::File.open_buffer(Development::DemoAssets.three_mf) { |archive| xml = archive.read("3D/3dmodel.model") }
    xml
  end

  def zip_model(xml, extra = {})
    Zip::OutputStream.write_buffer do |archive|
      { "3D/3dmodel.model" => xml }.merge(extra).each do |name, body|
        archive.put_next_entry(name)
        archive.write(body)
      end
    end.string
  end
end
