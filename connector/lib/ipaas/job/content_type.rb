module IPaaS
  module Job
    module ContentType
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :detect_content_type

      EXTENSION_MAP = {
        'pdf' => 'application/pdf',
        'png' => 'image/png',
        'jpg' => 'image/jpeg',
        'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'svg' => 'image/svg+xml',
        'webp' => 'image/webp',
        'json' => 'application/json',
        'xml' => 'application/xml',
        'csv' => 'text/csv',
        'txt' => 'text/plain',
        'zip' => 'application/zip',
      }.freeze

      DEFAULT_CONTENT_TYPE = 'application/octet-stream'.freeze

      class << self
        def detect_content_type(file_name)
          extension = file_name&.split('.')&.last&.downcase
          EXTENSION_MAP.fetch(extension, DEFAULT_CONTENT_TYPE)
        end
      end
    end
  end
end
