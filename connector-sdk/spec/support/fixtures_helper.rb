# Loads every connector fixture across both layouts.
# @return [void]
def load_all_fixtures
  load_fixture('*')
end

# Loads a connector fixture by name. Supports both the folder layout
# (fixtures/<name>/<name>.rb, where bundled SVGs live alongside the .rb) and the
# legacy flat layout (fixtures/<name>.rb). When both exist for the same name the
# folder copy wins.
# @param filename [String] fixture name or glob, e.g. 'debug_connector' or '*'
# @return [void]
def load_fixture(filename)
  fixture_entrypoints(filename).each { |f| require f }
end

# Resolves connector fixture entrypoint paths for +filename+ across both layouts,
# deduplicated so a folder entrypoint wins over a flat file of the same name.
# @param filename [String] fixture name or glob, e.g. 'debug_connector' or '*'
# @return [Array<String>] absolute paths of the connector entrypoint .rb files
def fixture_entrypoints(filename)
  dir = File.expand_path('../fixtures', __dir__)
  folder_files = Dir[File.join(dir, filename, '*.rb')].select { |f| folder_entrypoint?(f) }
  folder_names = folder_files.map { |f| File.basename(f, '.rb') }
  flat_files = Dir[File.join(dir, "#{filename}.rb")]
  flat_files.reject { |f| folder_names.include?(File.basename(f, '.rb')) } + folder_files
end

# A folder-layout entrypoint is fixtures/<name>/<name>.rb (basename == folder name).
# @param rb_path [String] path of a .rb file inside a fixture folder
# @return [Boolean]
def folder_entrypoint?(rb_path)
  File.basename(rb_path, '.rb') == File.basename(File.dirname(rb_path))
end
