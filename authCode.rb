#!/usr/local/bin/ruby -w
$LOAD_PATH.push("/home/hackathon/api_test/")
require 'General.rb'
require 'google/api_client'
require 'rest_client'
require 'mysql2'
require 'id_token.rb'

def get_refresh_token(user_code)
   notify "處理使用者代碼：#{user_code}"
   fake_auth = Google::APIClient::ClientSecrets.load.to_authorization 
   json_data = RestClient.post(
      fake_auth.token_credential_uri.to_s,
      :code=>user_code,
      :client_id=>fake_auth.client_id,
      :client_secret=>fake_auth.client_secret,
      :redirect_uri=>fake_auth.redirect_uri.to_s,
      :grant_type=>'authorization_code') 
   auth = JSON.parse(json_data)
   notify auth.inspect
   token = auth["refresh_token"]
   id_info = extract_id_token(auth["id_token"]) 
   id = id_info["id"]
   if token.nil? || token.empty?
      return get_token_from_db(id)
   else
      set_refresh_token(id,token)
      return token
   end
end


def get_token_from_db(id)
   my = Mysql2::Client.new(host:"localhost",username:"NAS",password:"hackathon",database:"hackathon")
   notify "搜尋ID：#{id}"
   res = my.query("SELECT * FROM user_token WHERE user_id = #{id}")
   token = nil
   notify "搜尋結果：#{res.each} "
   res.each do |row|
      token = row["refresh_token"]
      notify "TK:#{token}"
      break
   end
   notify "從資料庫中取得 #{id} 的 refresh token #{token}"
   return token
end

def set_refresh_token(id,refresh_t)

   my = Mysql2::Client.new(host:"localhost",username:"NAS",password:"hackathon",database:"hackathon")
   res = my.query("INSERT INTO `hackathon`.`user_token` (`user_id`, `refresh_token`) VALUES ('#{id}', '#{refresh_t}');")
   notify "已將#{id}的refresh token #{refresh_t}加入資料庫"
end


user_code = $stdin.readline
notify "新的使用者code：#{user_code}"
File.delete('_userCode') if File.exist?('_userCode')
File.open('_userCode','w') do |f|
   f.print(user_code)
end


refresh_token = get_refresh_token(user_code)
if !refresh_token.nil? && !refresh_token.empty?
   notify "新的refresh token:#{refresh_token}"
   File.delete('_refreshToken') if File.exist?('_refreshToken')
   File.open('_refreshToken','w') do |f|
      f.print(refresh_token)
   end
end
