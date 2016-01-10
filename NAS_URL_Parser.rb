#!/usr/local/bin/ruby -w
require 'json'
require 'General.rb'

class NAS_URL_Parser

   # intialize
   def initialize(url)
      @url = url
      clear_data
      parse_url 
   end

   # clear internal data
   def clear_data
      @type = nil # :fileBrowser_main
      @command = nil # :browse , :rename , :move_copy
      @fields = {} # key-value pair
      @domain = [] # array of :NAS , :Google
      @result = '' # a JSON representation of qurey result
      @polished = false
      @nas_token = nil
   end
   
   # parse url into internal data
   def parse_url
      set_url_type_and_command
      generate_field
      set_domain
   end


   # extract type and command from url
   def set_url_type_and_command
      if @url =~ %r{http://\d+.\d+.\d+.\d+/cmd,/ck6fup6/(.*)/(.*)\?}
         @type = $1.to_sym
         @command = $2.to_sym
      end
      notify "Type is #{@type} , Command is #{@command}"
   end
   
   # generate key-value fields
   def generate_field
      valid_part = @url.slice(%r{\?(.*)},1)
      url_list = valid_part.split('&')
      url_list.each do |pair_str|
         key, value = pair_str.split('=')
         next if value.nil?
         key_s = key.to_sym
         
         @fields[key_s] = value.chomp
         
         #===following is array store===#
         #if @fields[key_s].nil?
         #   @fields[key_s] = value.chomp
         #else
         #   array = [@fields[key_s]]
         #   array.push(value.chomp)
         #   @fields[key_s] = array
         #end
      end
      notify "Loaded Fields : "
      notify @fields.inspect
      fields_transform
   end

   # transform path into share and path
   def fields_transform 
      @fields[:share] = nil
      @fields[:dst_sharename] = nil
      @fields[:src_sharename] = nil
      @fields[:sharename] = nil

      case @type
      when :fileBrowser_main
         case @command
         when :browse
            field_path_transform(:share,:path) 
         when :move_copy
            field_path_transform(:dst_sharename,:dst_path) 
            field_path_transform(:src_sharename,:src_files) 
            field_path_transform(:src_sharename,:src_folders) 
         when :create_folder
            field_path_transform(:share,:path) 
         when :rename
            field_path_transform(:share,:new_path) 
            field_path_transform(:share,:old_path) 
         when :delete
            field_path_transform(:sharename,:files) 
            field_path_transform(:sharename,:folders) 
         when :state
            field_path_transform(:share,:path) 
         end
      end
      notify "Transformed Fields : "
      notify @fields.inspect
   end

   #fields transformer, give symbol to modify and store
   def field_path_transform(s_share,s_path)
      src_path = @fields[s_path]
      return if src_path.nil? || src_path.empty?
      notify "Spliting Path:#{s_path} to #{s_share}"
      result = path_transform(@fields[s_path])
      return if result.values.any?{|val| val.nil?}
      @fields[s_path] = result[:path]
      @fields[s_share] = result[:share]
      patch_url_from_field([s_share,s_path])
   end
   
   # patch url from fields
   def patch_url_from_field(syms = [])
      notify "URL replace, old : #{@url}"
      syms.each do |sym|
         pattern = sym.id2name
         if @url =~ /#{pattern}/
            @url.gsub!(%r{#{pattern}=([^&]*)},"#{pattern}=" + @fields[sym])
         else
            @url += "&#{pattern}=#{@fields[sym]}"
         end
      end
      notify "URL replace result : #{@url}"
   end
   # set domain cloud info
   def set_domain
      if check_fields_google_domain? # google domain
         @domain.push(:Google)
      elsif check_fields_nas_domain? # NAS domain
         @domain.push(:NAS)
      else 
         @domain.push(:Cross)
      end
      notify "DOMAIN : #{@domain}"
   end

   # Google Domain checker from fields
   def check_fields_google_domain?
      return true if @fields[:share] == "Google" # File Listing
      return true if @fields[:src_sharename] == "Google" && @fields[:dst_sharename] == "Google" # File Copy/Move
      return true if @fields[:sharename] == "Google" # File Deletion
      return false
   end

   # NAS Domain checker from fields
   def check_fields_nas_domain?
      return false if @fields[:share] == "Google" # File Listing
      return false if @fields[:src_sharename] == "Google" || @fields[:dst_sharename] == "Google" # File Copy/Move
      return false if @fields[:sharename] == "Google" # File Deletion
      return true
   end


   # did the domain is google? 
   def google?
      @domain.include?(:Google)
   end

   # did the domain is nas? 
   def nas?
      @domain.include?(:NAS)
   end

   # Polish result, different command has its won polish method
   def polish_result!(option = {})
      return @result.to_json if @polished
      revert_result = @result
      case @type
      when :fileBrowser_main
         case @command
         when :browse
            polish_result_browse!(revert_result,option)
         when :move_copy
            case @fields[:action]
            when "mv"
            when "cp"
            end
         when :create_folder
         when :rename
         when :delete
         when :state
         end
      end


      # notify polished
      @polished = true
      @result = revert_result
      return @result.to_json
   end

   # polish for browse : reorder the files
   def polish_result_browse!(revert_result,option = {})
      return if revert_result["files"].nil?
      list_result = revert_result["files"]
      list_result.sort! do |a,b|
         folder_a = a["_file_type"] == "folder"
         folder_b = b["_file_type"] == "folder"
         if folder_a && folder_b
            b["_file_name"] >= a["_file_name"] ? -1 : 1
         elsif folder_a && !folder_b
            -1
         elsif !folder_a && folder_b
            1
         else
            b["_file_name"] >= a["_file_name"] ? -1 : 1
         end
      end
      notify "Sorting Result"
      list_result.each do |f|
         notify %Q{#{f["_file_name"]}:#{f["_file_type"]}}
      end
   end



   # directly pass the url to nas
   def execute_nas
      login_result = login_nas
      @nas_token = login_result.cookies["authtok"]
      nas_result = RestClient.get(@url, {:cookies => login_result.cookies})
      notify "NAS:#{nas_result}"
      nas_result = patch_nas_result(nas_result)
      notify "NAS result:#{nas_result.inspect}"
      @result = nas_result
      @polished = true
   end



   
   # patch nas result, sort files, add sources, add download url 
   def patch_nas_result(old_result)
      # translate 

      result = JSON.parse(old_result)
      # insert source and download link
      if result["files"]
         result["files"].each do |hash|
            # download link
            share_name = CGI.escape("#{hash['_sharename']}")
            token = CGI.escape(@nas_token)
            path = CGI.escape("#{hash['_path']}")
            hash["download_url"] = "#{NAS_DOWNLOAD_URL}?shareName=#{share_name}&authtok=#{token}&path=#{path}"
            notify %Q{DL:#{hash["download_url"]}}
            # source
            hash["source"] = "NAS" 
         end
      end
      # sort files
      polish_result_browse!(result)
      # return
      return result
   end

   # execute command as google , result store in @result (JSON)
   def execute_google(client)
      case @type
      when :fileBrowser_main
         case @command
         when :browse
            @result = google_listing(client)
         when :move_copy
            case @fields[:action]
            when "mv"
               @result = google_move_file(client)
            when "cp"
               @result = google_copy_file(client)
            end
         when :create_folder
            @result = google_create_folder(client)
         when :rename
            @result = google_rename_file(client)
         when :delete
            @result = google_delete_file(client)
         when :state
            @result = google_check_exist(client)
         end
      end
      return @result
   end


   # Google : File Listing 
   def google_listing(client)
      notify "Run Google Listing.."
      escaped_path = @fields[:path]
      decoded_path = CGI::unescape(escaped_path)
      # this result is in hash format
      result = client.listing_path(decoded_path)
      return result
   end

   def move_copy_file_source
      src_array = []
      [@fields[:src_files],@fields[:src_folders]].each do |fs|
         if fs.is_a?(Array)
            src_array += fs
         elsif !fs.nil?
            src_array.push(fs)
         end
      end
      return src_array.collect {|p| CGI::unescape(p)}
   end

   # Google : Move File
   def google_move_file(client)
      notify "Command : Google move file"
      # result : error message
      # google treat folders as files
      src_files = move_copy_file_source
      dest_path = CGI::unescape(@fields[:dst_path].to_s)
      result = client.move_files(src_files,dest_path)

   end
   
   # Google : Copy File
   def google_copy_file(client)
      notify "Command : Google copy file"
      # result : error message
      # google treat folders as files
      src_files = move_copy_file_source
      dest_path = CGI::unescape(@fields[:dst_path].to_s)
      result = client.copy_files(src_files,dest_path)
   end

   # Google : Create Folder // Implementation : Recursively (analogize to mkdir -p <path>)
   def google_create_folder(client)
      path = CGI::unescape(@fields[:path].to_s)
      result = client.create_folder_by_path(path)
   end
   


   # Google : Rename File
   def google_rename_file(client)
      old_path = CGI::unescape(@fields[:old_path])
      new_path = CGI::unescape(@fields[:new_path])
      old_src = trim_to_dir_path(old_path) 
      new_src = trim_to_dir_path(new_path)
      if old_src != new_src
         # 來源目錄不同
         return {"errmsg0" => "Failure:Source directories are not the same"}
      else
         # 處理，給定某一個工作路徑，以及新檔案、舊檔案
         old_name = old_path.split('/')[-1]
         new_name = new_path.split('/')[-1]
         notify "已收到指令：在#{old_src}目錄中，將檔案#{old_name}改名為#{new_name}"
         client.rename_file_by_path(old_path,new_name)
      end

   end

   # Google : Delete FIle 
   def google_delete_file(client)
      files = []
      [@fields[:files],@fields[:folders]].each do |array|
         if array.is_a?(Array)
            files += array
         elsif !array.nil?
            files.push(array)
         end
      end
      targets = files.collect {|p| CGI::unescape(p)}
      client.delete_files_by_path(targets)
   end

   # Google : check file/folder exist
   def google_check_exist(client)
      path = CGI::unescape(@fields[:path])
      client.check_exist_by_path(path)
   end


   # Cross on move/copy
   def execute_cross(client)
      clear_tmp
      notify "Execute CROSS!!!"
      delete = false
      if @fields[:action] == "mv"
         delete = true
      end
      # judge direction
      if @fields[:src_sharename]!="Google" && @fields[:dst_sharename]=="Google"
         # NAS to Google
         @result = cross_nas_to_google(client,delete)
      else # Google to NAS
         @result = cross_google_to_nas(client,delete)
      end
      clear_tmp
   end

   # From Google to NAS
   def cross_google_to_nas(client,delete)
      notify "from Google to NAS"
      # download that file from google
      target = CGI.unescape(@fields[:src_files] || @fields[:src_folders])
      success = client.download_file(target)
      if !success
         return {"errmsg1" => "Fail to fetch from Google", "errmsg0" => "Failed"}.to_json
      end
      # upload it to nas
      dst_full_path = "/" + CGI.unescape("#{@fields[:dst_sharename]}#{@fields[:dst_path]}")
      success = do_nas_upload_all({:dst_full_path => dst_full_path})
      if !success
         return {"errmsg1" => "Fail to upload to NAS", "errmsg0" => "Failed"}.to_json
      else
         # success, remove files if delete is enabled
         if delete
            r = client.delete_files_by_path([target])
            notify "delete result:#{r.to_json}"
         end
         return {"errmsg1" => "OK", "errmsg0" => "OK"}.to_json
      end
   end 
   
   # Upload with NAS, anything in tmp folder
   def do_nas_upload_all(option)
      @dst_full_path = option[:dst_full_path]
      if @dst_full_path =~ %r{/$}
         @dst_full_path.chop!
      end
      @nas_cookies = login_nas.cookies
      notify "Upload all to #{@dst_full_path}"
      return do_nas_upload_recursive('/')
   end

   # upload files to nas recursively
   def do_nas_upload_recursive(path,depth = 0)
      return false if depth >= 50
      parent = "./tmp#{path}"
      Dir.new(parent).each do |name|
         if name != '..' && name != '.'
            notify "Name:#{name}"
            # each valid file or directory
            f = "#{parent}#{name}"
            if File.directory?(f)
               notify "#{depth}:dir:#{name}"
               r = create_folder(path+name)
               return false if !r
               do_nas_upload_recursive("#{path}#{name}/",depth + 1)
            else
               notify "#{depth}:file:#{name}"
               notify "File source : #{f}"
               r= do_nas_upload_file({:cookies => @nas_cookies, :dst_full_path => "#{@dst_full_path}#{path}" , :src_path => f })
               notify "NAS upload : #{r}"
               return false if r !~ /"success": true/
            end
         end
      end
   end

   # create folder with full path
   def create_folder(path)
      notify "Path:#{path}"
      full_path = @dst_full_path + path
      r = path_transform(full_path,false)
      url = sprintf(NAS_FOLDER_CREATE_URL,CGI.escape(r[:path]),CGI.escape(r[:share]))
      notify "create folder with #{url}"
      result = RestClient.get(url, {:cookies => @nas_cookies})
      notify "create result#{result.inspect}"
      return result == "{\"errmsg0\": \"OK\"}"
   end


   # From NAS to Google
   def cross_nas_to_google(client,delete)
      notify "from NAS to Google"
      # download all from NAS
      src_path = ''
      src_type = nil
      if !@fields[:src_files].nil?
         src_path = @fields[:src_files]
         src_type = "text"
      elsif !@fields[:src_folders].nil?
         src_path = @fields[:src_folders]
         src_type = "folder"

      end
      src_path = CGI.unescape(src_path)
      res = download_all_to_tmp(src_path,src_type)
      if !res
         return {"errmsg1" => "Fail to download from NAS", "errmsg0" => "Fail"}.to_json
      end
      # upload all to google
      res = client.upload_all_in_tmp(CGI.unescape(@fields[:dst_path]))
      if res
         if delete
            # delete files from NAS
            nas_delete_by_path(src_path,src_type)
         end
         return {"errmsg1" => "OK", "errmsg0" => "OK"}.to_json
      else
         return {"errmsg1" => "Fail to upload to Google", "errmsg0" => "Fail"}.to_json
      end

   end



   def nas_delete_by_path(src_path,src_type)
      type_sym = src_type == "folder" ? :folders : :files
      res = RestClient.get(NAS_DELETE_URL , {:params => {:sharename => @fields[:src_sharename] , type_sym => src_path} , :cookies => @nas_cookies})
      if res.code == 200
         notify "Delete #{src_path} SUCCESS"
         return true
      else
         notify "Delete #{src_path} FAILUR"
         return false
      end
      
   end


   def download_all_to_tmp(src_path,src_type)
      notify "NAS : download to tmp : #{src_path}, type is #{src_type}"
      @root_path = "#{`pwd`.chomp}/tmp"
      notify "current in #{@root_path}"
      refresh_nas_token
      download_file_recursively(src_path,src_type,"")
   end

   def refresh_nas_token
      @nas_cookies = login_nas.cookies
      @nas_token = @nas_cookies["authtok"]
   end

   def download_file_recursively(remote_path,remote_type,current_path)
      notify "recursively download #{remote_path} (#{remote_type}) to #{current_path}"
      file_path = @root_path + current_path
      filename = remote_path.split("/")[-1]
      if remote_type == "text"
         # normal file
         res = RestClient.get(NAS_DOWNLOAD_URL, {:params => {:shareName => @fields[:src_sharename], :authtok => @nas_token , :path => remote_path }})
         return false if res.code != 200
         final_path = "#{file_path}/#{filename}"
         notify "寫入檔案：#{final_path}"
         IO.binwrite(final_path,res)
      else
         notify "Remote is folder"
         build_path = "#{file_path}/#{filename}"
         notify "Create dir:#{build_path}"
         # mkdir
         Dir.mkdir(build_path)
         # list all in remote

         url = sprintf(NAS_FILE_LIST_URL,CGI.escape(remote_path),@fields[:src_sharename],@nas_token)
         notify "URL:#{url}"
         res = RestClient.get(url,{:cookies => @nas_cookies})
         notify res
         JSON.parse(res)["files"].each do |file|
            notify "Has : #{file['_file_name']}, type : #{file['_file_type']}"
            res = download_file_recursively("#{remote_path}/#{file['_file_name']}",file['_file_type'],"#{current_path}/#{filename}")
            return false if !res
         end

      end
      return true

   end


end
