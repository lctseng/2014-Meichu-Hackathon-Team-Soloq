#!/usr/local/bin/ruby -w

require 'google/api_client'
require 'mime/types'
require 'json'
require 'rest_client'
require 'General.rb'

class GoogleDrive
   def initialize(access_token = nil)
      @client = Google::APIClient.new({:application_name => "File Browser" ,:auto_refresh_token => true })
      @client.authorization = Google::APIClient::ClientSecrets.load.to_authorization
      #@client.authorization.code = load_user_code
      @client.authorization.refresh_token = load_refresh_token
      if access_token.nil?
         @client.authorization.access_token = refresh_access_token(@client)
      else
         @client.authorization.access_token = access_token
      end
      #@client.authorization.access_token = refresh_access_token(@client)
   end

   def access_token
      @client.authorization.access_token
   end

   def load_user_code
      code = nil
      File.open('_userCode') do |f|
         code = f.readline
      end
      return code
   end

   def load_refresh_token
      token = nil
      File.open('_refreshToken') do |f|
         token = f.readline
      end
      return token
   end


   # Refresh Access Token
   def refresh_access_token(client)
      auth = client.authorization
      data = {
         :client_id => auth.client_id,
         :client_secret => auth.client_secret,
         :refresh_token => auth.refresh_token,
         :grant_type => "refresh_token"
      }
      @response = JSON.parse(RestClient.post "https://accounts.google.com/o/oauth2/token", data) 
      notify "Refresh Response:#{@response.inspect}"
      if !@response["access_token"].nil?
         return @response["access_token"]
      else
         notify "No Valid Access Tokens"
         return nil
      end
   rescue RestClient::BadRequest => e
      # Bad request
      notify "Bad Http Request : #{e.inspect}"
   rescue
      # Something else bad happened
   end




   # access drive
   def drive
      @drive ||= @client.discovered_api('drive','v2')
   end

   # access client
   def client
      @client
   end

   def upload_temp_file(filename,target_path)
      filepath = "../upload/#{filename}"
      upload_file("../upload/",filename,{:parent_path => target_path})

   end

   def upload_file(filepath,filename,option = {})
      notify "options:#{option.inspect}"
      if option[:parent_id]
         parent_id = option[:parent_id]
      else
         parent_id = find_dir_id(option[:parent_path])
      end

      full_path = filepath+filename
      mime =  MIME::Types.type_for(full_path)
      file = Google::APIClient::UploadIO.new(full_path,mime)
      metadata = {
         title:  filename.force_encoding('UTF-8'),
         parents: [{id:parent_id}]
      }
      notify "Google : upload file :#{full_path}"
      result = client.execute(
         api_method: drive.files.insert,
         body_object: metadata,
         media: file,
         parameters: {
            'uploadType' => 'multipart'
         }
      )
      #notify result.inspect
      if result.status == 200
         return '{"success": true, "msg": ""}'
      else
         return '{"success": false, "msg": "Google : Fail to upload"}'
      end
   end


   # List files in specific path,
   # undefine when there are more than 2 folders have same name in the same folder
   def listing_path(path)
      search_id = find_dir_id(path)
      notify "Google : Listing Path : #{path}"
      # final folder id is 'search_id'
      return list_folder_by_id(search_id)
   end

   # List all file with folder id
   def list_folder_by_id(id)
      notify "Listing in #{id}"
      hash_result = {}
      result = @client.execute(
         api_method: drive.files.list,
         parameters: {q:%Q{"#{id}" in parents and not trashed}}
      )
      if result.status != 200
         notify "Error occured when LIST:#{result.inspect}}"
      end
      ordered_files = []
      result.data.items.each do |item|
         file_info = {}
         # File name
         file_info["_file_name"] = item.title
         # MIME type
         file_info["mime_type"] = item.mime_type
         # File type & Size
         if item.mime_type =~ %r{application/vnd.google-apps.folder}
            # folder
            file_info["_file_type"] = "folder"
            file_info["_file_size"] = "0"
         else
            # otherwise
            notify "Non-folder:#{item.title}"
            file_info["_file_type"] = "text"
            size_str = item.fileSize.to_s rescue  "0" 
            file_info["_file_size"] = size_str
         end
         # Modified Date
         file_info["_date_modified"] = item.modifiedDate.getlocal("+08:00").strftime("%Y-%m-%d %H:%M:%S")
         # downLoad URL
         file_info["download_url"]  = (item.downloadUrl + "&access_token=#{access_token}") rescue nil
         # Icon URL
         file_info["icon_url"]  = item.iconLink rescue nil
         # Thumbnail Link
         file_info["thumbnail_url"] = item.thumbnailLink rescue nil
         # File ID
         file_info["file_id"]  = item.id rescue nil
         # Google docs process:docx pptx xlsx
         exp_link,ext = proper_export_link(item)
         if exp_link
            # special data source
            file_info["source"] = "Google_doc"
            if !exp_link.empty?
               file_info["download_url"] = (exp_link + "&access_token=#{access_token}")
            end
            file_info["edit_link"] = item.alternateLink rescue nil
            
         end
         


         # Data source 
         file_info["source"] = "Google" if file_info["source"].nil?
         # Store in list
         ordered_files.push(file_info)
      end

      #notify "Files:#{ordered_files}" 
      # filling info
      hash_result["files"] = ordered_files
      hash_result["total"] = result.data.items.size
      return hash_result
   end

   # get proper export link
   def proper_export_link(item)
      url_linl = nil
      ext = nil
      # Google docs process:docx pptx xlsx
      if  item.mime_type =~ %r{application/vnd.google-apps.(document|presentation|spreadsheet)}
         # get export tokens
         if $1 == 'document'
            url_link = item.exportLinks['application/vnd.openxmlformats-officedocument.wordprocessingml.document'] 
            ext = 'docx'
         elsif $1 == 'presentation'
            url_link = item.exportLinks['application/vnd.openxmlformats-officedocument.presentationml.presentation'] 
            ext = 'pptx'
         elsif $1 == 'spreadsheet'
            url_link = item.exportLinks['application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'] 
            ext = 'xlsx'

         end
      end
      return [url_link,ext]
   end

   # Move multiple files to dest path
   def move_files(src_files,dest_path)
      file_ok = []
      file_no = []
      notify "Move #{src_files.inspect} to '#{dest_path}'"
      dst_id = find_dir_id(dest_path)
      src_files.each do |src_file|
         file_id = get_file_id(src_file)
         if !file_id
            notify "File:#{src_file} :Not found"
            file_no.push(src_file)
            next
         end
         file_meta = get_file_by_id(file_id)
         file_meta.parents = [{id: dst_id}]
         notify "Move #{file_id} to #{dst_id}"
         result = client.execute(
            api_method: drive.files.update,
            body_object: file_meta,
            parameters:{fileId:file_id} 
         )
         if result.status==200
            file_ok.push(src_file)
            notify "Success"
         else
            file_no.push(src_file)
            notify "Failure"
         end
      end
      # Generate result
      r_hash = {}
      if file_ok.empty? && file_no.empty?
         # None is success
         r_hash["errmsg0"] = "Failed"
         r_hash["errmsg1"] = "No files to operate"
      elsif !file_no.empty?
         # Someone is failed
         r_hash["errmsg0"] = "Failed"
         r_hash["errmsg1"] = "FAILED:#{file_no.join(',')}"
      else
         r_hash["errmsg0"] = r_hash["errmsg1"] = "OK"
      end
      return r_hash

      
   end



   # Copy multiple files to dest path
   def copy_files(src_files,dest_path)
      file_ok = []
      file_no = []
      notify "Copy #{src_files.inspect} to '#{dest_path}'"
      dst_id = find_dir_id(dest_path)
      src_files.each do |src_file|
         file_id = get_file_id(src_file)
         result = copy_file_recursively(file_id,dst_id)
         if result
            file_ok.push(src_file)
            notify "Copy of #{src_file} SUCCESS"
         else
            file_no.push(src_file)
            notify "Copy of #{src_file} FAILURE"
         end
      end
      # Generate result
      r_hash = {}
      if file_ok.empty? && file_no.empty?
         # None is success
         r_hash["errmsg0"] = "Failed"
         r_hash["errmsg1"] = "No files to operate"
      elsif !file_no.empty?
         # Someone is failed
         r_hash["errmsg0"] = "Failed"
         r_hash["errmsg1"] = "FAILED:#{file_no.join(',')}"
      else
         r_hash["errmsg0"] = r_hash["errmsg1"] = "OK"
      end
      return r_hash

      
   end


   
   # Recursively Copy the file, Max Depth is 200 
   def copy_file_recursively(file_id,dst_id,depth = 0)
      notify "recursive copy (depth:#{depth}): #{file_id} to #{dst_id}"
      if !file_id
         notify "File ID:#{file_id} :Not found"
         return false
      end
      if depth >= 200
         notify "Stack level too Deep, Abort."
         return false
      end
      file_meta = get_file_by_id(file_id)
      # type check
      if meta_is_folder?(file_meta)
         notify "ID : #{file_id} is a folder"
         # create 
         folder_id = create_folder_under_parent(file_meta.title,dst_id)
         if !folder_id.nil? 
            notify "Create folder '#{file_meta.title}' under #{dst_id} SUCCESS, new id : #{folder_id}"
            # New folder created, load origin files under old older
            result = client.execute(
               api_method: drive.files.list,
               parameters: {q:%Q{"#{file_id}" in parents and not trashed}}
            )
            part_result = true
            result.data.items.each do |item|
               part_result &&= copy_file_recursively(item.id,folder_id,depth+1)   
            end
         else
            notify "Create folder '#{file_meta.title}' under #{dst_id} FAILED"
            return false
         end
      else
         copied_file = drive.files.copy.request_schema.new({
            'title' => file_meta.title,
            'parents' => [{id: dst_id}]
         })
         result = client.execute(
            :api_method => drive.files.copy,
            :body_object => copied_file,
            :parameters => { 'fileId' => file_id }
         )
         return result.status==200
      end
   end
     
   # Create folder under parent folder(specify by ID)
   def create_folder_under_parent(title,parent_id)
      metadata = {
         title: title,
         mimeType: 'application/vnd.google-apps.folder',
         parents: [{id: parent_id}]
      }
      result = client.execute(
         api_method: drive.files.insert,
         body_object: metadata
      )
      if result.status == 200
         return result.data.id
      else
         return nil
      end
   end


   # Check file meta whether a folder or not
   def meta_is_folder?(meta)
      return meta.mime_type =~ %r{application/vnd.google-apps.folder}
   end



   # Get id of a file
   # Undefine when two file have same name
   def get_file_id(path) 
      # get directory id
      dir_id = find_dir_id(trim_to_dir_path(path))
      if !dir_id # Directory not found
         return false
      end
      filename = path.split('/')[-1]
      # retrive that file
      result = @client.execute(
         api_method: drive.files.list,
         parameters: {q:%Q{"#{dir_id}" in parents and title = "#{filename}" and not trashed}}
      )
      item = result.data.items[0]
      if item
         file_id = result.data.items[0].id
         notify "File ID for #{filename} : #{file_id}"
      else
         @errmsg = "File:#{path} Not Found"
         file_id = nil
      end
      return file_id
   end

   # Get file meta by id
   def get_file_by_id(id)
      notify "Get id : #{id}"
      result = @client.execute(
         api_method: drive.files.get,
         parameters: { fileId: id}
      )
      #notify "File :#{result.data.title} , Tumb. URI : #{result.data.inspect}"
      return result.data
   end


   # Get ID of a directory
   def find_dir_id(path,root_id = 'root')
      dirs = path.split('/').select{|s| !s.empty?}
      notify "Desending Path : #{dirs.inspect}"
      search_id = root_id
      # recursive iteration search
      dirs.each do |dir_name|
         part_result = @client.execute(
            api_method: drive.files.list,
            parameters: {q: %Q{"#{search_id}" in parents and title = "#{dir_name}" and not trashed}}
         )
         notify part_result.inspect if part_result.status != 200
         # if error is some folder cannot foundm return id as false
         if part_result.data.items.empty?
            @errmsg = "Folder:#{dir_name} Not Found"
            return false
         end

         #notify part_result.inspect
         part_result.data.items.each do |item|
            notify "In: #{search_id} : #{item.title}"
            search_id = item.id
         end

      end
      return search_id
   end

   # List all file in Google Drive
   def list_file
      result = @client.execute(
         api_method: drive.files.list
      )
      notify "LIST RESULT : #{result.data.inspect}" 
      result.data.items.each do |item|
         if item.mime_type =~ %r{application/vnd.google-apps.folder}
            notify "Folder : #{item.title} , ID : #{item.id} , parent #{item.parents.inspect}"
         else
            notify "#{item.title} : #{item.fileSize} : #{item.id}"
         end
      end
      notify "R:#{result.inspect}"
      notify result.data.items.inspect

   end

   # Create folder by path 
   def create_folder_by_path(path)  
      notify "Create folder : #{path}"
      dirs = path.split('/').select{|s| !s.empty?}
      status = true
      error_msg = ''
      created = false
      search_id = 'root'
      dirs.each do |dir_name|
         notify "Descending to #{search_id}"
         # check if that folder exist in current search directory
         search_res = client.execute(
            api_method: drive.files.list,
            parameters: {q:%Q{"#{search_id}" in parents and title = "#{dir_name}"}}
         )
         if search_res.data.items.empty? # Not found
            new_id = create_folder_under_parent(dir_name,search_id)
            if new_id.nil?
               error_msg = "Fail to create #{dir_name} under #{search_id}"
               status = false
               break
            end
            created = true
            search_id = new_id
         else
            # Found , go into first item it found
            search_id = search_res.data.items[0].id
         end

      end
      if status
         if created
            return {"errmsg0" => "OK"}
         else
            return {"errmsg0" => "Nothing to be created"}
         end
      else
         return {"errmsg0" => error_msg}
      end
   end


   # Rename file in specific path
   def rename_file_by_path(old_path,new_name)
      # find that file
      file_id = get_file_id(old_path)
      if !file_id
         notify "File:#{old_path} :Not found"
         return {"errmsg0" => "Failure:File Not Found"}
      end
      file_meta = get_file_by_id(file_id)
      file_meta.title = new_name
      result = client.execute(
         api_method: drive.files.update,
         body_object: file_meta,
         parameters:{fileId:file_id} 
      )
      return {"errmsg0" => "OK"}


   end

   # delete every file in files
   def delete_files_by_path(src_files)
      file_ok = []
      file_no = []
      notify "Delete #{src_files.inspect} "
      src_files.each do |src_file|
         file_id = get_file_id(src_file)
         result = delete_file_recursively(file_id)
         if result
            file_ok.push(src_file)
            notify "Delete of #{src_file} SUCCESS"
         else
            file_no.push(src_file)
            notify "Delete of #{src_file} FAILURE"
         end
      end
      # Generate result
      r_hash = {}
      if file_ok.empty? && file_no.empty?
         # None is success
         r_hash["errmsg0"] = "Failed"
         r_hash["errmsg1"] = "No files to operate"
      elsif !file_no.empty?
         # Someone is failed
         r_hash["errmsg0"] = "Failed"
         r_hash["errmsg1"] = "FAILED:#{file_no.join(',')}"
      else
         r_hash["errmsg0"] = r_hash["errmsg1"] = "OK"
      end
      return r_hash


   end
   
   # Recursively delete the file, Max Depth is 200 
   def delete_file_recursively(file_id,depth = 0)
      notify "recursive delete (depth:#{depth}): #{file_id} "
      if !file_id
         notify "File ID:#{file_id} :Not found"
         return false
      end
      if depth >= 200
         notify "Stack level too Deep, Abort."
         return false
      end
      file_meta = get_file_by_id(file_id)
      # type check
      part_result = true
      if meta_is_folder?(file_meta)
         notify "ID : #{file_id} is a folder"
         # list all file under it
         result = client.execute(
            api_method: drive.files.list,
            parameters: {q:%Q{"#{file_id}" in parents and not trashed}}
         )
         # delete its sub files
         result.data.items.each do |item|
            part_result &&= delete_file_recursively(item.id,depth+1)   
         end
      end
      # target is a file, or after delete all files in a folder
      result = client.execute(
         :api_method => drive.files.delete,
         :parameters => { 'fileId' => file_id }
      )
      return part_result && result.status==204
      
   end

   # Check file with that path exist?
   def check_exist_by_path(path) 
      # try to get id
      id = get_file_id(path)
      if !id
         return {"_filestatues" => "not exist", "errmsg0" => @errmsg}
      else
         return {"_filestatues" => "exist"}
      end
   end


   # download that file/folder under tmp, build the tree
   def download_file(src_path)
      notify "Google : download to tmp : #{src_path}"
      file_id = get_file_id(src_path)
      @root_path = "#{`pwd`.chomp}/tmp"
      notify "current in #{@root_path}"

      download_file_recursively(file_id,"")
   end

   def download_file_recursively(file_id,current_path)
      notify "recursively download #{file_id} to #{current_path}"
      file = get_file_by_id(file_id)
      file_path = @root_path + current_path
      exp_link, ext = proper_export_link(file)
      if exp_link
         file_url = exp_link
         ext = ".#{ext}"
      else
         file_url = file.download_url rescue nil
      end
      if file_url # if it is download-able 
         result = client.execute(:uri => file_url)
         if result.status == 200
            file_content = result.body
            final_path = "#{file_path}/#{file.title}#{ext}"
            notify "寫入檔案：#{final_path}"
            IO.binwrite(final_path,file_content)
            return true
         else
            notify "Error in download : #{file.title}"
            return false
         end
      else
         # may be a folder, create a same one here 
         dir_path = "#{current_path}/#{file.title}"
         build_path = "#{file_path}/#{file.title}"
         notify "Create dir:#{build_path}"
         Dir.mkdir(build_path)
         result = client.execute(
            api_method: drive.files.list,
            parameters: {q:%Q{"#{file_id}" in parents and not trashed}}
         )
         result.data.items.each do |item|
            res =  download_file_recursively(item.id,dir_path)
            return false if !res
         end

         return true
      end
   end

   
   def upload_all_in_tmp(target_path)
      parent_id = find_dir_id(target_path)
      path = "#{`pwd`.chomp}/tmp"
      upload_under_to_parent_id(path,parent_id)
   end

   
   def upload_under_to_parent_id(under_path,parent_id)
      notify "Set all under #{under_path} to #{parent_id}"
      Dir.new(under_path).each do |name|
         if name != '..' && name != '.'
            # each valid file or directory
            f = "#{under_path}/#{name}"
            notify "check on:#{f}"
            if File.directory?(f)
               new_id = create_folder_under_parent(name,parent_id)
               notify "New folder with ID :#{new_id}"
               res = upload_under_to_parent_id(f,new_id)
               notify "File:#{name} status : #{res}"
               return false if !res
            else
               notify "Special:#{f}"
               res = upload_file(under_path+"/",name,{:parent_id => parent_id})
               notify res
               return false if res !~ /"success": true/
            end
         end
      end
      return true
      

   end




end

