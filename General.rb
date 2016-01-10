#!/usr/local/bin/ruby -w

require 'rest_client'

NAS_IP = "140.113.17.23"
NAS_LOGIN_URL = "http://#{NAS_IP}/adv,/cgi-bin/weblogin.cgi?password=hackathon&username=admin"
NAS_DOWNLOAD_URL = "http://#{NAS_IP}/adv,/cgi-bin/file_download.cgi"
NAS_UPLOAD_URL = "http://#{NAS_IP}/adv,/cgi-bin/file_upload-cgic"
NAS_FOLDER_CREATE_URL = "http://#{NAS_IP}/cmd,/ck6fup6/fileBrowser_main/create_folder?path=%s&share=%s"
NAS_FILE_LIST_URL = "http://#{NAS_IP}/cmd,/ck6fup6/fileBrowser_main/browse?fstatus=waiting&limit=100&path=%s&share=%s&start=0&view=grid&authtok=%s"
NAS_DELETE_URL = "http://#{NAS_IP}/cmd,/ck6fup6/fileBrowser_main/delete"

def notify(*args)
   File.open("Log","a") do |f|
      f.puts(*args)
   end
end


# trim file path to directory path
def trim_to_dir_path(path)
   return path.slice(%r{/([^/]+/)+}) || '/'
end

# path transform 
def path_transform(src_path,escaped = true)
   slash = escaped ? '%2F' : '/'
   share = nil
   path = nil
   if src_path =~ %r{#{slash}(.*?)(#{slash}.*)}
      share = $1
      path = $2
      notify "New share:#{share},New Path:#{path}"
   end

   return {:share => share,:path => path}
end

# Extract access token 
def access_token_extract(access_t_str)
   return access_t_str.slice(%r{access_token:([^,\n\t {}]*)},1)
end


# clear temp folder 
def clear_tmp
   notify "Cleaning tmp..."
   notify `cd /home/hackathon/api_test/tmp && rm -rf *`
end

# Login as NAS
def login_nas
   login_url = NAS_LOGIN_URL
   login_result = RestClient.get(login_url)
   notify "NAS login result:#{login_result}"
   return login_result
end
   
# Upload with NAS, single file
def do_nas_upload_file(option)
   if option[:cookies].nil?
      nas_cookies = login_nas.cookies
   else
      nas_cookies = option[:cookies]
   end
   result = RestClient.post( NAS_UPLOAD_URL,
   {
       :rformat => "extjs",
       :target_path => option[:dst_full_path],
       :file_path => File.new(option[:src_path], 'rb')
     },
     {:cookies => nas_cookies}               
   )
   return result
end
