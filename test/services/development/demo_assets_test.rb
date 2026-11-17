require "minitest/autorun"
require "nokogiri"
require "stringio"
require_relative "../../../lib/development/demo_assets"

class DevelopmentDemoAssetsTest < Minitest::Test
  def test_stl_is_an_outward_wound_watertight_cube_with_scaling
    text = Development::DemoAssets.stl(scale: 2)
    assert text.ascii_only?
    assert_match(/\Asolid .*\n.*endsolid .*\n\z/m, text)
    triangles = text.scan(/outer loop\s+(.*?)\s+endloop/m).map do |(facet)|
      facet.scan(/vertex ([^\n]+)/).map { |(coordinates)| coordinates.split.map(&:to_f) }
    end
    assert_equal 12, triangles.size
    assert_equal 8, triangles.flatten(1).uniq.size
    assert_equal [0.0, 40.0], triangles.flatten(1).flatten.minmax
    assert_watertight(triangles)
    assert_in_delta 64_000, signed_volume(triangles), 0.001
    assert_equal text, Development::DemoAssets.stl(scale: 2)
  end

  def test_three_mf_has_valid_stored_zip_records_and_a_buildable_mesh
    bytes = Development::DemoAssets.three_mf
    entries = read_stored_zip(bytes)
    assert_equal ["[Content_Types].xml", "_rels/.rels", "3D/3dmodel.model"], entries.keys
    entries.each_value { |xml| assert Nokogiri::XML(xml) { |config| config.strict.nonet } }

    relationships = Nokogiri::XML(entries.fetch("_rels/.rels"))
    relation = relationships.at_xpath("//*[local-name()='Relationship']")
    assert_equal "/3D/3dmodel.model", relation["Target"]
    assert_equal "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel", relation["Type"]
    types = Nokogiri::XML(entries.fetch("[Content_Types].xml"))
    assert_equal "application/vnd.ms-package.3dmanufacturing-3dmodel+xml",
      types.at_xpath("//*[local-name()='Default'][@Extension='model']")["ContentType"]

    model = Nokogiri::XML(entries.fetch("3D/3dmodel.model"))
    namespaces = { "m" => "http://schemas.microsoft.com/3dmanufacturing/core/2015/02" }
    assert_equal "millimeter", model.root["unit"]
    object = model.at_xpath("/m:model/m:resources/m:object", namespaces)
    assert_equal "model", object["type"]
    assert_equal object["id"], model.at_xpath("/m:model/m:build/m:item", namespaces)["objectid"]
    vertices = object.xpath("m:mesh/m:vertices/m:vertex", namespaces).map { |vertex| %w[x y z].map { |axis| Float(vertex[axis]) } }
    triangles = object.xpath("m:mesh/m:triangles/m:triangle", namespaces).map do |triangle|
      %w[v1 v2 v3].map { |index| vertices.fetch(Integer(triangle[index])) }
    end
    assert_equal 8, vertices.size
    assert_equal 12, triangles.size
    assert_watertight(triangles)
    assert_in_delta 8_000, signed_volume(triangles), 0.001
    assert_equal bytes, Development::DemoAssets.three_mf
  end

  def test_png_has_valid_chunks_and_a_colored_320_by_200_raster
    bytes = Development::DemoAssets.png(color: "#0f766e")
    io = StringIO.new(bytes)
    assert_equal "\x89PNG\r\n\x1a\n".b, io.read(8)
    chunks = []
    until io.eof?
      size, type = io.read(8).unpack("Na4")
      data = io.read(size)
      assert_equal Zlib.crc32(type + data), io.read(4).unpack1("N"), "Invalid #{type} checksum"
      chunks << [type, data]
    end
    assert_equal %w[IHDR IDAT IEND], chunks.map(&:first)
    assert_equal [320, 200, 8, 2, 0, 0, 0], chunks.first.last.unpack("NNCCCCC")
    scanlines = Zlib::Inflate.inflate(chunks[1].last)
    assert_equal 200 * (1 + 320 * 3), scanlines.bytesize
    rows = scanlines.bytes.each_slice(1 + 320 * 3).map do |row|
      assert_equal 0, row.shift
      row.each_slice(3).to_a
    end
    assert_equal [241, 245, 249], rows[0][0]
    assert_equal [15, 118, 110], rows[120][120]
    assert_operator rows.flatten(1).uniq.size, :>=, 5
    assert_equal bytes, Development::DemoAssets.png(color: "#0f766e")
    refute_equal bytes, Development::DemoAssets.png(color: "#b45309")
  end

  def test_invalid_sizes_and_colors_are_rejected
    [0, -1, Float::INFINITY, Float::NAN, nil, "invalid"].each do |scale|
      assert_raises(ArgumentError) { Development::DemoAssets.stl(scale: scale) }
      assert_raises(ArgumentError) { Development::DemoAssets.three_mf(scale: scale) }
    end
    [nil, "teal", "#123", "#gggggg"].each do |color|
      assert_raises(ArgumentError) { Development::DemoAssets.png(color: color) }
    end
  end

  private

  def assert_watertight(triangles)
    edges = triangles.flat_map { |a, b, c| [[a, b], [b, c], [c, a]] }
    edges.group_by { |a, b| [a, b].sort }.each_value do |pair|
      assert_equal 2, pair.size, "Every mesh edge must be shared by two triangles"
      assert_equal pair.first.reverse, pair.last, "Adjacent faces must use opposite edge directions"
    end
  end

  def signed_volume(triangles)
    triangles.sum do |a, b, c|
      (a[0] * (b[1] * c[2] - b[2] * c[1]) +
        a[1] * (b[2] * c[0] - b[0] * c[2]) +
        a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
    end
  end

  def read_stored_zip(bytes)
    io = StringIO.new(bytes)
    entries = {}
    offsets = []
    while bytes.byteslice(io.pos, 4) == [0x04034b50].pack("V")
      offsets << io.pos
      header = io.read(30).unpack("VvvvvvVVVvv")
      assert_equal 0, header[3], "Fixture ZIP entries must be stored without compression"
      assert_equal header[7], header[8]
      name = io.read(header[9])
      io.read(header[10])
      content = io.read(header[7])
      assert_equal header[6], Zlib.crc32(content)
      entries[name] = content
    end
    directory_offset = io.pos
    entries.keys.each_with_index do |name, index|
      central = io.read(46).unpack("VvvvvvvVVVvvvvvVV")
      assert_equal 0x02014b50, central[0]
      assert_equal name, io.read(central[10])
      assert_equal offsets[index], central[16]
      io.read(central[11] + central[12])
    end
    directory_size = io.pos - directory_offset
    assert_equal [0x06054b50, 0, 0, entries.size, entries.size, directory_size, directory_offset, 0],
      io.read(22).unpack("VvvvvVVv")
    assert io.eof?
    entries
  end
end
