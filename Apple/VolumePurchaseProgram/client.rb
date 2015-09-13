module Apple
  module VolumePurchaseProgram
    class Client

      # Per Apple's suggestion in the MDM documentation
      MAX_CONCURRENCY = 5

      # The keys that give us results in requests
      SERVICE_RESULTS_KEYS = {
        getUsers:    :users,
        getLicenses: :licenses
      }.freeze

      # Maps a service to a URL, these are retrieved in #init
      SERVICE_URLS = {}

      Response = Struct.new(:results, :count, :since_modified_token)

      def initialize(url: 'https://vpp.itunes.apple.com/WebObjects/MZFinance.woa/wa/', stoken:, client_guid:, client_host:)
        @stoken = stoken

        manager = Typhoeus::Hydra.new(max_concurrency: MAX_CONCURRENCY)
        @server_connection = Faraday.new(url: url, parallel_manager: manager) do |faraday|
          faraday.adapter  :typhoeus
          faraday.response :multi_json, symbolize_keys: true
        end

        # TODO cache these results & bust the cache on url moved error (9617)
        response = @server_connection.get URI.join(url, 'VPPServiceConfigSrv')
        response.body.each do |key, value|
          if match = key.to_s.match(/^(?<service_name>.+)SrvUrl$/)
            SERVICE_URLS[match[:service_name].to_sym] = value
          end
        end

        client_config = request(:clientConfig)

        # Check the client context, if it's empty set it claiming this VPP instance
        if client_context = client_config[:clientContext]
          client_context = MultiJson.load client_context, symbolize_keys: true
        else
          new_client_context = MultiJson.dump({hostname: client_host, guid: client_guid})
          client_config = request(:clientConfig, clientContext: new_client_context)
          client_context = MultiJson.load(client_config[:clientContext], symbolize_keys: true)
        end
        unless client_context[:hostname] == client_host && client_context[:guid] == client_guid
          raise "Hostname and GUID, #{client_context[:hostname]} #{client_context[:guid]}, does not match expected values"
        end
      end

      def request(service, in_parallel: false, **params)
        response = @server_connection.get(SERVICE_URLS[service]) do |request|
          request.body = MultiJson.dump params.merge(sToken: @stoken)
        end
        # If we're doing parallel requests don't check for success and jazz here, just return
        # the raw request for processing after the block is done; just doing this for shorthand
        if in_parallel
          response
        else
          raise_if_unsuccessful response
          response.body
        end
      end

      def raise_if_unsuccessful(response)
        unless response.success? && response.body[:status] == 0
          raise "Error #{response.body.fetch(:errorNumber)}: #{response.body.fetch(:errorMessage)}"
        end
      end

      def batched_request(service, since_modified_token:, **params)
        first_response = request(service, in_parallel: true, sinceModifiedToken: since_modified_token)
        remaining_requests = first_response.body[:totalBatchCount] - 1
        batch_token = first_response.body[:batchToken]
        responses = [first_response]

        # Spin up the remaining requests in parellel
        @server_connection.in_parallel do
          remaining_requests.times.map do |i|
            responses << request(service, in_parallel: true, batchToken: batch_token, overrideIndex: i + 1)
          end
        end

        # Grab the key we care about, flatten, and kill any nils
        merged_results = responses.map do |response|
          raise_if_unsuccessful response
          response.body.fetch SERVICE_RESULTS_KEYS[service], []
        end.flatten.compact

        Response.new(merged_results, merged_results.count, responses.last[:sinceModifiedToken])
      end

      def get_users(since_modified_token: nil)
        batched_request :getUsers, since_modified_token: since_modified_token, includeRetired: 1
      end

      def get_licenses(since_modified_token: nil)
        batched_request :getLicenses, since_modified_token: since_modified_token
      end
    end
  end
end
