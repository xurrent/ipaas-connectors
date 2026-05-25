def load_all_fixtures
  load_fixture('*')
end

def load_fixture(filename)
  Dir[File.expand_path(File.join(File.dirname(__FILE__),'../fixtures',"#{filename}.rb"))].each {|f| require f}
end