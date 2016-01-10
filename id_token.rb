require 'General.rb'
require 'rest_client'
require 'jwt'
require 'mysql2'

def extract_id_token(id_token)
   cert_str_json  = RestClient.get("https://www.googleapis.com/oauth2/v1/certs")
   cert_strs = JSON.parse(cert_str_json).values
   cert_strs.each do |cert_str|
      cert =OpenSSL::X509::Certificate.new(cert_str)
      key = cert.public_key
      begin
         @token = JWT.decode(id_token,key,false)
         break
      rescue
         next
      end
   end
   notify "取得的token資訊：#{@token}"
   return @token[0]

end





