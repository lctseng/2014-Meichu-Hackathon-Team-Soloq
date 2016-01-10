#!/usr/local/bin/ruby -w

$LOAD_PATH.push("/home/hackathon/api_test/")

require "GoogleDrive.rb"
require "NAS_URL_Parser.rb"



input = $stdin.readline
notify "INPUT:#{input}"
url_str , access_t_str = input.split

notify "acc_str:#{access_t_str}"

access_t = access_token_extract(access_t_str)

result = '' # store result in JSON
notify "================================="
notify Time.now.to_s
notify "---------------------------------"

notify "URL：#{url_str}"
notify "Access Token：#{access_t}"

url = NAS_URL_Parser.new(url_str)
client = GoogleDrive.new(access_t)



if url.google?
   url.execute_google(client)
elsif url.nas?
   url.execute_nas
else 
   url.execute_cross(client)
end

## after execute commands
result = url.polish_result!


#notify "Query Result:"
#notify result
puts result


#client.list_file


