require "paperclip/aws/core/version"

module Paperclip
  module Storage
    module AwsCore
      def self.extended base
        begin
          require 'aws-core-sdk'
        rescue LoadError => e
          e.message << " (You may need to install the aws-core-sdk gem)"
          raise e
        end unless defined?(Aws)


        base.instance_eval do
          @s3_options     = @options[:s3_options]     || {}
        
          @s3_endpoint    = @options[:s3_endpoint]
          
          if @options[:credentials].present?
            credentials = @options[:credentials].symbolize_keys
            ::Aws::config[:credentials] = ::Aws::Credentials.new(credentials[:access_key_id], credentials[:secret_access_key])
            ::Aws.config[:region] = credentials[:region]
          end
            
          @aws_credentials = @options[:credentials]   || {}

          @s3_protocol    = @options[:s3_protocol]    ||
            Proc.new do |style, attachment|
              permission  = (@s3_permissions[style.to_s.to_sym] || @s3_permissions[:default])
              permission  = permission.call(attachment, style) if permission.respond_to?(:call)
              (permission == :public_read) ? 'http' : 'https'
            end

          unless @options[:url].to_s.match(/\A:s3.*url\Z/) || @options[:url] == ":asset_host"
            @options[:path] = @options[:path].gsub(/:url/, @options[:url]).gsub(/\A:rails_root\/public\/system/, '')
            @options[:url]  = ":s3_path_url"
          end
          @options[:url] = @options[:url].inspect if @options[:url].is_a?(Symbol)

          @http_proxy = @options[:http_proxy] || nil
        end

        Paperclip.interpolates(:s3_alias_url) do |attachment, style|
          "#{attachment.s3_protocol(style, true)}//#{attachment.s3_host_alias}/#{attachment.path(style).gsub(%r{\A/}, "")}"
        end unless Paperclip::Interpolations.respond_to? :s3_alias_url
        Paperclip.interpolates(:s3_path_url) do |attachment, style|
          "#{attachment.s3_protocol(style, true)}//#{attachment.s3_host_alias}/#{attachment.path(style).gsub(%r{\A/}, "")}"
        end unless Paperclip::Interpolations.respond_to? :s3_path_url
        Paperclip.interpolates(:s3_domain_url) do |attachment, style|
          "#{attachment.s3_protocol(style, true)}//#{attachment.s3_host_alias}/#{attachment.path(style).gsub(%r{\A/}, "")}"
        end unless Paperclip::Interpolations.respond_to? :s3_domain_url
        Paperclip.interpolates(:asset_host) do |attachment, style|
          "#{attachment.path(style).gsub(%r{\A/}, "")}"
        end unless Paperclip::Interpolations.respond_to? :asset_host
      end

      def expiring_url(time = 3600, style_name = default_style)
        if path(style_name)
          base_options = { :expires => time, :secure => use_secure_protocol?(style_name) }
          s3_object(style_name).url_for(:read, base_options.merge(s3_url_options)).to_s
        else
          url(style_name)
        end
      end

      def s3_credentials
        # @s3_credentials ||= parse_credentials(@options[:s3_credentials])
      end

      def s3_host_name
        host_name = @options[:s3_host_name] ||  "s3.amazonaws.com"
        # host_name = host_name.call(self) if host_name.is_a?(Proc)
        # 
        # host_name || s3_credentials[:s3_host_name] || "s3.amazonaws.com"
      end

      def s3_host_alias
        @s3_host_alias = @options[:host_alias] || "#{s3_host_name}/#{bucket_name}"
        @s3_host_alias
      end

      def s3_url_options
        s3_url_options = @options[:s3_url_options] || {}
        s3_url_options = s3_url_options.call(instance) if s3_url_options.respond_to?(:call)
        s3_url_options
      end

      def bucket_name
        @bucket = @options[:bucket] || s3_credentials[:bucket]
        @bucket = @bucket.call(self) if @bucket.respond_to?(:call)
        @bucket or raise ArgumentError, "missing required :bucket option"
      end

      def s3_interface
        @s3_interface ||= begin
          config = { } # :s3_endpoint => s3_host_name }

          obtain_s3_instance_for(config.merge(@s3_options))
        end
      end

      def obtain_s3_instance_for(options)
        instances = (Thread.current[:paperclip_s3_instances] ||= {})
        instances[options] ||= s3_endpoint.present? ? ::Aws::S3.new(endpoint: s3_endpoint) : ::Aws.s3
      end
      
      def s3_endpoint
        @s3_endpoint
      end


      def exists?(style = default_style)
        if original_filename
          s3_interface.get_object(bucket: bucket_name, key: style)
          true
        else
          false
        end
      rescue => e
        false
      end


      def s3_protocol(style = default_style, with_colon = false)
        protocol = @s3_protocol
        protocol = protocol.call(style, self) if protocol.respond_to?(:call)

        if with_colon && !protocol.empty?
          "#{protocol}:"
        else
          protocol.to_s
        end
      end

      def flush_writes #:nodoc:
        @queued_for_write.each do |style, file|
          begin
            log("saving #{path(style)}")

            write_options = {
              bucket: bucket_name, 
              key: path(style), 
              acl: 'public-read', 
              body: File.read(file.path), 
              content_type: file.content_type
            }

            
            s3_interface.put_object(write_options)
          rescue => e
            log("Error: #{e.inspect}")
            # create_bucket
            # retry
          ensure
            file.rewind
          end
        end

        after_flush_writes # allows attachment to clean up temp files

        @queued_for_write = {}
      end

      def flush_deletes #:nodoc:
        @queued_for_delete.each do |path|
          begin
            log("deleting #{path}")
            s3_interface.delete_object(bucket: bucket_name, key: path.sub(%r{\A/},''))
          rescue Aws::Errors::Base => e
            # Ignore this.
          end
        end
        @queued_for_delete = []
      end

      
      def copy_to_local_file(style, local_dest_path)
      
        log("copying #{path(style)} to local file #{local_dest_path}")
        local_file = ::File.open(local_dest_path, 'wb')
        file = s3_interface.get_object(bucket: bucket_name, key: path(style))
        file.body.pos = 0 
        local_file.write(file.body.read)
        local_file.close
      rescue AWS::Errors::Base => e
        warn("#{e} - cannot copy #{path(style)} to local file #{local_dest_path}")
        false
      end

      private
      def use_secure_protocol?(style_name)
        s3_protocol(style_name) == "https"
      end

    end
  end
end
