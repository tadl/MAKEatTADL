require "zlib"

module Development
  # Small, deterministic fixture files. These contain no imported models or metadata.
  module DemoAssets
    VERTICES = [[0, 0, 0], [1, 0, 0], [1, 1, 0], [0, 1, 0],
                [0, 0, 1], [1, 0, 1], [1, 1, 1], [0, 1, 1]].map(&:freeze).freeze
    TRIANGLES = [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7],
                 [0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5],
                 [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]].map(&:freeze).freeze
    NORMALS = [[0, 0, -1], [0, 0, 1], [0, -1, 0], [1, 0, 0], [0, 1, 0], [-1, 0, 0]].map(&:freeze).freeze
    WIDTH = 320
    HEIGHT = 200

    module_function

    def stl(scale: 1)
      vertices = scaled_vertices(scale)
      facets = TRIANGLES.each_with_index.map do |triangle, index|
        points = triangle.map { |vertex| "      vertex #{vertices[vertex].join(' ')}" }.join("\n")
        "  facet normal #{NORMALS[index / 2].join(' ')}\n    outer loop\n#{points}\n    endloop\n  endfacet"
      end
      "solid demo_cube\n#{facets.join("\n")}\nendsolid demo_cube\n"
    end

    def three_mf(scale: 1)
      vertices = scaled_vertices(scale).map { |x, y, z| %(<vertex x="#{x}" y="#{y}" z="#{z}"/>) }.join
      triangles = TRIANGLES.map { |a, b, c| %(<triangle v1="#{a}" v2="#{b}" v3="#{c}"/>) }.join
      model = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <resources><object id="1" type="model"><mesh><vertices>#{vertices}</vertices><triangles>#{triangles}</triangles></mesh></object></resources>
          <build><item objectid="1"/></build>
        </model>
      XML
      content_types = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml"/>
        </Types>
      XML
      relationships = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Target="/3D/3dmodel.model" Id="model" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"/>
        </Relationships>
      XML
      stored_zip("[Content_Types].xml" => content_types, "_rels/.rels" => relationships, "3D/3dmodel.model" => model)
    end

    def png(color: "#0f766e")
      unless color.is_a?(String) && color.match?(/\A#[0-9a-f]{6}\z/i)
        raise ArgumentError, "color must be a six-digit hex color beginning with #"
      end
      base = color.delete_prefix("#").scan(/../).map { |channel| channel.to_i(16) }
      pixels = Array.new(HEIGHT) { Array.new(WIDTH, [241, 245, 249]) }
      (154..184).each do |y|
        half_width = (82 * Math.sqrt([1 - ((y - 169) / 15.0)**2, 0].max)).floor
        ((160 - half_width)..(160 + half_width)).each { |x| pixels[y][x] = [221, 229, 236] }
      end
      fill_polygon(pixels, [[82, 73], [160, 113], [160, 174], [82, 134]], base)
      fill_polygon(pixels, [[160, 113], [238, 73], [238, 134], [160, 174]], base.map { |channel| (channel * 0.76).round })
      fill_polygon(pixels, [[160, 33], [238, 73], [160, 113], [82, 73]], base.map { |channel| (channel * 0.72 + 255 * 0.28).round })

      scanlines = pixels.map { |row| "\0".b + row.flatten.pack("C*") }.join.b
      header = [WIDTH, HEIGHT, 8, 2, 0, 0, 0].pack("NNCCCCC")
      "\x89PNG\r\n\x1a\n".b + png_chunk("IHDR", header) +
        png_chunk("IDAT", Zlib::Deflate.deflate(scanlines)) + png_chunk("IEND", "".b)
    end

    def scaled_vertices(scale)
      side = Float(scale) * 20
      raise ArgumentError unless side.finite? && side.positive?

      VERTICES.map { |vertex| vertex.map { |coordinate| coordinate * side } }
    rescue ArgumentError, TypeError
      raise ArgumentError, "scale must produce a positive, finite size"
    end
    private_class_method :scaled_vertices

    def fill_polygon(pixels, points, color)
      first_y, last_y = points.map(&:last).minmax
      (first_y...last_y).each do |y|
        scan_y = y + 0.5
        intersections = points.each_with_index.filter_map do |(x1, y1), index|
          x2, y2 = points[(index + 1) % points.size]
          next unless (y1 <= scan_y && scan_y < y2) || (y2 <= scan_y && scan_y < y1)

          x1 + (scan_y - y1) * (x2 - x1) / (y2 - y1).to_f
        end.sort
        intersections.each_slice(2) do |left, right|
          ((left - 0.5).ceil..(right - 0.5).floor).each { |x| pixels[y][x] = color }
        end
      end
    end
    private_class_method :fill_polygon

    def png_chunk(type, data)
      [data.bytesize].pack("N") + type.b + data + [Zlib.crc32(type.b + data)].pack("N")
    end
    private_class_method :png_chunk

    # Fixed DOS epoch timestamps and stored entries keep the tiny archive reproducible.
    def stored_zip(entries)
      archive = "".b
      directory = "".b
      entries.each do |name, content|
        name = name.b
        content = content.b
        checksum = Zlib.crc32(content)
        offset = archive.bytesize
        archive << [0x04034b50, 20, 0, 0, 0, 33, checksum, content.bytesize, content.bytesize, name.bytesize, 0].pack("VvvvvvVVVvv")
        archive << name << content
        directory << [0x02014b50, 20, 20, 0, 0, 0, 33, checksum, content.bytesize, content.bytesize,
          name.bytesize, 0, 0, 0, 0, 0, offset].pack("VvvvvvvVVVvvvvvVV")
        directory << name
      end
      end_record = [0x06054b50, 0, 0, entries.size, entries.size, directory.bytesize, archive.bytesize, 0].pack("VvvvvVVv")
      archive + directory + end_record
    end
    private_class_method :stored_zip
  end
end
