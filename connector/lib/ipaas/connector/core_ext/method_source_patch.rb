module MethodSource
  # Override the caching in this class to ensure our solution files have a key that uniquely defines
  # the file in a specific solution version

  class << self
    alias original_lines_for lines_for
    alias original_clear_cache clear_cache

    def lines_for(file_name, name = nil)
      if use_uuid_cache?(file_name)
        IPaaS::Connector::Common::SolutionFileCache.lines_for(file_name)
      else
        original_lines_for(file_name, name)
      end
    end

    def use_uuid_cache?(file_name)
      file_name.start_with?(IPaaS.solution_directory)
    end

    def clear_cache
      IPaaS::Connector::Common::SolutionFileCache.clear
      original_clear_cache
    end
  end
end
