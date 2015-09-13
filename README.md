# VPP-Client

Usage:

    CLIENT_GUID = '75523bc2-b2e0-4d15-81d6-41d5d4754ad7'.freeze
    CLIENT_HOST = 'example.com'.freeze

    client = Apple::VolumePurchaseProgram::Client.new(
      stoken: File.read('stoken.txt'),
      client_guid: CLIENT_GUID,
      client_host: CLIENT_HOST
    )
    user_request = client.get_users(since_modified_token: 'KJLssdSDIj332mVNURFEtMzk4OTE=')
    license_request = client.get_licenses(since_modified_token: 'MTQ0M339jgzNy0wLVNURFEtMzk4OTE=')
    puts license_request.count
    puts user_request.results.inspect
