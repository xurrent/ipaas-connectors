module IPaaS
  module Job
    module PsaAuth
      extend ActiveSupport::Concern
      extend IPaaS::Connector::Common::ProcRules::ProcSafe

      proc_safe :psa_validate_secret, :psa_extract_basic_auth, :psa_generate_secret_for,
                :psa_secret_for, :psa_delete_secret_for

      # Validates a Basic Auth request against stored or configured credentials.
      # Checks inbound_connection config first; falls back to outbound_connection store.
      #
      # @param request [Object] HTTP request with #headers
      # @param strict [Boolean] use strict Base64 decoding (default: true)
      def psa_validate_secret(request, strict: true)
        user_name, password = psa_extract_basic_auth(request, strict: strict)
        encrypted_secret = resolve_credential(user_name)
        authentication_failure! if encrypted_secret.blank?

        decrypted_secret = decrypt_secret_string(encrypted_secret)
        authentication_failure! unless password == decrypted_secret
      end

      # Extracts username and password from a Basic Auth header.
      #
      # @param request [Object] HTTP request with #headers
      # @param strict [Boolean] use strict Base64 decoding (default: true);
      #   pass false to tolerate non-standard encodings (e.g. trailing newlines)
      # @return [Array<String>] [user_name, password]
      def psa_extract_basic_auth(request, strict: true)
        user_name, password = basic_auth_credentials(request.headers, strict: strict)
        authentication_failure! if user_name.blank? || password.blank?

        [user_name, password]
      end

      # Generates a UUID secret and stores it for the given user.
      #
      # @param user_name [String] the PSA user name
      # @return [String] the encrypted secret
      def psa_generate_secret_for(user_name)
        secret = make_secret_string(SecureRandom.uuid)
        outbound_connection.store.write(user_secret_key(user_name), secret)
        secret
      end

      # Reads the stored secret for the given user.
      #
      # @param user_name [String] the PSA user name
      # @return [String, nil] the encrypted secret or nil
      def psa_secret_for(user_name)
        outbound_connection.store.read(user_secret_key(user_name))
      end

      # Deletes the stored secret for the given user.
      #
      # @param user_name [String] the PSA user name
      def psa_delete_secret_for(user_name)
        outbound_connection.store.delete(user_secret_key(user_name))
      end

      private

      def user_secret_key(user_name)
        "secret##{user_name}"
      end

      def resolve_credential(user_name)
        if inbound_connection.config[:user_name].present?
          authentication_failure! unless user_name == inbound_connection.config[:user_name]
          inbound_connection.config[:password]
        else
          psa_secret_for(user_name)
        end
      end

      def authentication_failure!
        fail_job!('Invalid basic authentication header.')
      end
    end
  end
end

IPaaS::Job::Context.extension(IPaaS::Job::PsaAuth)
