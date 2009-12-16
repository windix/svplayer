#!/usr/bin/ruby
require 'rubygems'
require 'patron'
require 'digest/md5'
require 'zlib'
require 'stringio'
require 'pp'

require "#{File.dirname(__FILE__)}/multipart"

class SVPlayerTool
  
  def initialize(video_filename)
    @video_filename = video_filename
    video_extname = File.extname(video_filename) # with .
    @video_basename = video_filename[0 ... -video_extname.length]
  end

  def fetch
    data, headers = Multipart::Post.prepare_query(build_query_fields_hash)
  
    sess = Patron::Session.new
    sess.connect_timeout = 10000 # milliseconds
    sess.timeout = 120 # seconds
    # sess.insecure = true # don't validate SSL

    sess.base_url = "http://svplayer.shooter.cn"
    sess.headers.merge!(headers) 
  
    sess.headers['User-Agent'] = 'SPlayer Build' # 'SPlayer Build 959'
    sess.headers['Accept'] = '*/*'
    
    pp sess.headers if $DEBUG
    pp data if $DEBUG

    resp = sess.post("/api/subapi.php", data)

    puts resp.status if $DEBUG
    puts resp.body.length if $DEBUG
    
    @resp = resp.body
    File.open("#{@video_basename}.data", "w") { |f| f.write(@resp) } if $DEBUG

    parse_response
  end

  def debug
    @resp = File.open(@video_filename).read
    parse_response
  end

  private
  
  def calc_file_hash
    file_length = File.size(@video_filename)

    offset = []
    if (file_length >= 8192)
      offset[0] = 4096
      offset[1] = file_length / 3 * 2
      offset[2] = file_length / 3
      offset[3] = file_length - 8192
    end

    file_hash = []
    offset.each do |o|
      file_hash << Digest::MD5.hexdigest(IO.read(@video_filename, 4096, o))
    end

    file_hash
  end

  def build_query_fields_hash
    fields_hash = {}
    fields_hash['pathinfo'] = @video_filename
    fields_hash['filehash'] = calc_file_hash.join(';')
    #fields_hash['vhash'] = 'ae44f1c3be6004153ac3f74ae42cd91f'
    fields_hash['shortname'] = ''
  
    fields_hash
  end

  def extract_subtitle_data(f, file_name) 
    single_file_pack_length, file_ext_name_length = f.read(8).unpack("N2")
    
    ext_name = f.read(file_ext_name_length)
    
    puts "single_file_pack_length = #{single_file_pack_length}, file_ext_name_length = #{file_ext_name_length}, ext_name = #{ext_name}" if $DEBUG
    
    file_full_name = file_name + "." + ext_name
    
    puts "Extract file #{file_full_name}..."

    file_length = f.read(4).unpack("N").first
    
    puts "file_length = #{file_length}" if $DEBUG
    
    file_gz_data = f.read(file_length)
    
    puts "file_gz_data.length = #{file_gz_data.length}" if $DEBUG

    begin
      gz = Zlib::GzipReader.new(StringIO.new(file_gz_data))
      sub_file = gz.read    
    rescue Zlib::GzipFile::Error => e
      sub_file = file_gz_data
    end

    File.open("#{file_name}.#{ext_name}", "w") do |fout|
      fout.write(sub_file)
    end
  end

  def parse_response
    puts "length: #{@resp.length}" if $DEBUG

    StringIO.open(@resp) do |f|
      count = f.read(1).unpack("C").first
      puts "count = #{count}" if $DEBUG
      
      if (count == 255) 
        puts "Cannot find subtitle"
      else
        (1..count).each do |i|
          puts "[#{i}]" if $DEBUG

          package_length, desc_length = f.read(8).unpack("N2")
          puts "package_length = #{package_length}, desc_length = #{desc_length}" if $DEBUG

          if (desc_length > 0)
            desc = f.read(desc_length).unpack("C*")
          end
          
          file_data_length, file_count = f.read(5).unpack("NC")
          puts "file_data_length = #{file_data_length}, file_count = #{file_count}" if $DEBUG

          (1..file_count).each do
            extract_subtitle_data(f, "#{@video_basename}.#{i}")
          end 
        end 
      end
    
    end
  end


end


if $0 == __FILE__
  if ARGV.length != 1
    puts "Usage: #{$0} <video_file>"

  else
    video_file = ARGV[0]
    video_file_ext_name = File.extname(video_file)

    valid_video_ext_names = %w{.avi .mkv .ts .mp4}
    if valid_video_ext_names.include?(video_file_ext_name)
      svp = SVPlayerTool.new(video_file)
      svp.fetch
    else
      puts "Skip with ext name: '#{video_file_ext_name}'"
    end
  end
end
