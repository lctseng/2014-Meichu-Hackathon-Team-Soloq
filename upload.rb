#!/usr/local/bin/ruby -w

$LOAD_PATH.push("/home/hackathon/api_test/")

require "General.rb"
require "GoogleDrive.rb"



input = $stdin.readline
temp_name , full_target_path ,  access_t_str = input.split

temp_name = CGI.unescape(temp_name)
full_target_path = CGI.unescape(full_target_path)

notify "tok str#{access_t_str}"

access_t = access_token_extract(access_t_str)


result = '' # store result in JSON
notify "***UPLOAD***================================="
notify Time.now.to_s
notify "---------------------------------"

notify "Access Token：#{access_t}"

notify "Full Path:#{full_target_path}"

_res = path_transform(full_target_path,false)

target_share = _res[:share]
target_path = _res[:path]

temp_path = "../upload/#{temp_name}"

notify "Temp File is #{temp_name}, Target Share is #{target_share} ,Targe path #{target_path}"
if target_share == "Google"
   client = GoogleDrive.new(access_t)
   result = client.upload_temp_file(temp_name,target_path)
else
   result = do_nas_upload_file({:dst_full_path => full_target_path, :src_path => temp_path})
end

# delete that file
File.delete(temp_path)

puts result

