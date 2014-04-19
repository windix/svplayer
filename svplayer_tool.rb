#!/usr/bin/env ruby
# coding: UTF-8

require 'bundler/setup'
require 'patron'
require 'digest/md5'
require 'zlib'
require 'stringio'
require 'pp'
require 'charlock_holmes/string'
require 'multiparty'

# $DEBUG = true

class SVPlayerTool
  
  def initialize(video_filename)
    @video_filename = video_filename
    video_extname = File.extname(video_filename) # with .
    @video_basename = video_filename[0 ... -video_extname.length]
  end

  def fetch
    multiparty = Multiparty.new
    multiparty << build_query_fields_hash

    sess = Patron::Session.new
    sess.connect_timeout = 10000 # milliseconds
    sess.timeout = 120 # seconds
    # sess.insecure = true # don't validate SSL

    sess.base_url = "http://svplayer.shooter.cn"
    
    sess.headers['Content-Type'] = multiparty.header_value
    sess.headers['User-Agent'] = 'SPlayer Build' # 'SPlayer Build 959'
    sess.headers['Accept'] = '*/*'
    
    pp sess.headers if $DEBUG
    pp multiparty.body if $DEBUG

    resp = sess.post("/api/subapi.php", multiparty.body)

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
    {
      'pathinfo' => @video_filename,
      'filehash' => calc_file_hash.join(';'),
      #'vhash' => 'ae44f1c3be6004153ac3f74ae42cd91f',
      'shortname' => ''
    }
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
      # not gz compressed
      sub_file = file_gz_data
    end

    begin
      sub_file.detect_encoding! 

      unless sub_file.encoding.to_s == 'UTF-8'
        sub_file = CharlockHolmes::Converter.convert sub_file, sub_file.encoding.to_s, 'UTF-8'
      end
    rescue
      puts "Failed to detect encoding"
      return
    end

=begin
    require 'iconv' unless String.method_defined?(:encode)
    if String.method_defined?(:encode)
        sub_file.encode!('UTF-8', 'UTF-8', :invalid => :replace)
    else
        ic = Iconv.new('UTF-8', 'UTF-8//IGNORE')
        sub_file = ic.iconv(file_contents)
    end
=end

    raise Exception.new if sub_file =~ /splayer\.org/

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
            extract_subtitle_data f, (i == 1) ? @video_basename : "#{@video_basename}.#{i}"
          end
        end 
      end
    end
  end

end


if $0 == __FILE__

  def no_subtitle_file_found_for(video_file)
    srt_file_ext_names = %w{ .srt .ass }

    escaped_path = video_file.chomp(File.extname(video_file)).gsub(/([\[\]\{\}\*\?\\])/, '\\\\\1')

    # matching with 'abc.srt', 'abc.chn.srt' etc
    Dir["#{escaped_path}*{#{srt_file_ext_names.join(',')}}"].length == 0
  end

  if ARGV.length == 0
    puts "Usage: #{$0} <video_file>"
  else
    valid_video_ext_names = %w{.avi .mkv .ts .mp4}

    ARGV.each do |video_file|
      if valid_video_ext_names.include?(File.extname(video_file)) &&
        no_subtitle_file_found_for(video_file)
        
        puts "Search for #{File.basename(video_file)}:"
        
        svp = SVPlayerTool.new(video_file)

        retry_times = 0
        begin
          svp.fetch
        rescue => e
          retry_times += 1
          
          if retry_times > 3
            raise
          else
            puts "Fake subtitle found... retry no.#{retry_times}"
            sleep 5
            retry
          end
        end
      else
        puts "Skip #{video_file}..."
      end
    end
  end
end
