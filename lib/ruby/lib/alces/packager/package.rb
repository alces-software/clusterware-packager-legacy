################################################################################
# (c) Copyright 2007-2012 Alces Software Ltd & Stephen F Norledge.             #
#                                                                              #
# Symphony - Operating System Content Deployment Framework                     #
#                                                                              #
# This file/package is part of Symphony                                        #
#                                                                              #
# Symphony is free software: you can redistribute it and/or modify it under    #
# the terms of the GNU Affero General Public License as published by the Free  #
# Software Foundation, either version 3 of the License, or (at your option)    #
# any later version.                                                           #
#                                                                              #
# Symphony is distributed in the hope that it will be useful, but WITHOUT      #
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or        #
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public License #
# for more details.                                                            #
#                                                                              #
# You should have received a copy of the GNU Affero General Public License     #
# along with Symphony.  If not, see <http://www.gnu.org/licenses/>.            #
#                                                                              #
# For more information on the Symphony Toolkit, please visit:                  #
# https://github.com/alces-software/symphony                                       #
#                                                                              #
################################################################################
require 'alces/packager/dao'
require 'alces/packager/semver'
require 'alces/tools/core_ext/module/delegation'
require 'dm-aggregates'
require 'digest/md5'

module Alces
  module Packager
    class Package
      class << self
        def with_both_repos(&block)
          if (res = block.call).nil? && DataMapper::Repository.adapters.key?(:global)
            repository(:global) do
              res = block.call
            end
          end
          res
        end

        def compiler(name, version = nil)
          with_both_repos do
            if version.nil?
              first(:path.like => "compilers/#{name}/%", :default => true) || first(:path.like => "compilers/#{name}/%")
            else
              first(:path.like => "compilers/#{name}/%", :version => version)
            end
          end
        end
        
        # have affinity for currently selected compiler
        def resolve(descriptor, compiler_tag = nil)
          with_both_repos do 
            path, op, version = descriptor.split(' ')
            packages = all(path: path)
            if packages.empty? && !compiler_tag.nil?
              packages = all(:path.like => "#{path}/%", compiler_tag: compiler_tag)
            end
            if packages.empty?
              packages = all(:path.like => "#{path}/%")
            end
            resolve_for_version(packages, op, version)
          end
        end

        def resolve_for_version(packages, op, version)
          if op.nil?
            # XXX - this doesn't take into account what version has been set as the default...
            packages.first
          else
            matcher = case op
                      when '<>', '!='
                        lambda { |p| p.version != version }
                      when '=', '=='
                        lambda { |p| p.version == version }
                      when '>='
                        lambda { |p| p.version >= version }
                      when '>'
                        lambda { |p| p.version > version }
                      when '<'
                        lambda { |p| p.version < version }
                      when '<='
                        lambda { |p| p.version <= version }
                      when '~>'
                        # clever operator; ~> 1.0 = 1.* ; 1.0.0 = 1.0.*
                        split = version.split('.')[0..-2]
                        lower_bound = split.join('.')
                        upper_bound = split.tap { |a| a[-1] = a[-1].to_i + 1 }.join('.')
                        lambda do |p|
                begin
                  p_semver = Semver.new(p.version)
                  p_semver.satisfies("~ #{lower_bound}.*") &&
                    p_semver.satisfies("<= #{upper_bound}")
                rescue ArgumentError
                  p.version >= lower_bound && p.version <= upper_bound
                end
              end
                      else
                        raise 'Invalid requirement operator: #{op}'
                      end
            packages.sort do |a,b|
              begin
                Semver.new(b.version) <=> Semver.new(a.version)
              rescue
                b.version <=> a.version
              end
            end.find(&matcher)
          end
        end
        
        def write_aliases!
          File.open(File.expand_path(File.join(Config.modules_dir,'.aliases')), 'w') do |io|
            Package.all.each do |p|
              p.aliases.each do |k,v|
                io.puts "module-alias #{k} #{v}"
              end
              if p.type == 'compilers'
                if Package.count(name: p.name) > 1 && p.default?
                  io.puts "module-version #{p.path} default"
                end
              else
                if Package.count(name: p.name, version: p.version) > 1 && p.default?
                  io.puts "module-version #{p.path} default"
                end
              end
            end
            Version.all.each do |v|
              if Version.all(path: v.path).length > 1 && v.default?
                io.puts "# module-version #{v.path}/#{v.version} default"
              end
            end
          end
        end

        def write_defaults!
          Package.all(default: true, :type.not => 'compilers').each do |p|
            versionfile_name = File.join(Config.modules_dir, p.type, p.name, p.version, '.version')
            #raise ModulefileError, "Failed to write module file #{versionfile_name} (already exists)" if File.exists?(versionfile_name)
            if File.directory?(File.dirname(versionfile_name))
              raise ModulefileError, "Failed to write module file #{versionfile_name}" unless File.write(versionfile_name, ModuleTree.versionfile_for(p.tag))
            else
              path = [p.type, p.name, p.version].join('/')
              IoHandler.warning("No directory found for #{path}; please purge #{path}")
            end
          end
        end          
      end

      include DataMapper::Resource

      property :id, Serial
      property :type, String
      property :name, String
      property :version, String
      property :tag, String
      property :compiler_tag, String
      property :path, String
      property :default, Boolean

      before :save do
        self.path = [type, name, version, tag].compact.join('/')
        self.default = (comparable_packages.empty? || 
                        (comparable_packages.length == 1 && comparable_packages.first.id == self.id))
      end

      after :save do
        opts = {
          path: [type, name].join('/'), version: version
        }
        Version.create(opts) if Version.first(opts).nil?
      end

      after :destroy do
        count = comparable_packages.length
        if count == 0
          Version.all(path: [type, name].join('/'), version: version).destroy
        elsif count == 1
          comparable_packages.update(default: true)
        end
      end

      def comparable_packages
        @comparable_packages = if type == 'compilers'
                                 Package.all(name: name)
                               else
                                 Package.all(name: name, version: version)
                               end
      end

      def aliases
        { [alias_prefix, alias_suffix].join('-') => path }.tap do |h|
          # h[[alias_prefix, version].join('-')] = path if default?
          if type == 'compilers'
            # compilers also have alias pointing to runtime libs
            lib_path = path.split('/').tap{ |a| a.shift }.unshift('libs').join('/')
            h[[compiler_libs_alias_prefix, alias_suffix].join('-')] = lib_path
            #h[[compiler_libs_alias_prefix, version].join('-')] = lib_path if default?
          end
        end
      end

      def alias_prefix
        "#{type}-#{name}"
      end

      def compiler_libs_alias_prefix
        "libs-#{name}"
      end
      
      def alias_suffix
        Digest::SHA1.hexdigest(path)[0..7]
      end

      def renderer(metadata, opts)
        requirements = opts[:requirements]
        if opts[:compiler]
          requirements.unshift(Package.resolve(opts[:compiler]))
        end
        if type == 'compilers'
          CompilerModuleFileRenderer.new(self, metadata, requirements, opts)
        else
          ModuleFileRenderer.new(self, metadata, requirements, opts)
        end
      end

      class ModuleFileRenderer < Struct.new(:package, :metadata, :requirements, :opts)
        delegate :type, :name, :version, :tag, to: :package
        delegate :description, :centred_summary, :top_title_bar, :bottom_title_bar,
                 :url, :help, :license, :license_help, to: :metadata

        def params
          opts[:params].map{|k,v| "#{k}=#{v}"}.join(" ")
        end

        def modules
          opts[:modules].reject{|m| m =~ /compilers\//}.join(', ')
        end

        def package_dir
          File.expand_path(File.join(Config.packages_dir, package.path))
        end

        def modulefile_path
          File.expand_path(File.join(Config.modules_dir, package.path))
        end

        def caps_name
          name.upcase.tr('-+','_')
        end

        def package_specifics
          metadata.module_content rescue nil
        end

        def package_dependencies
          "".tap do |s|
            requirements.map do |r|
              case r.type
              when 'compilers'
                s << "depend #{r.compiler_libs_alias_prefix} #{r.version} #{r.alias_suffix}\n"
              else
                s << "depend #{r.alias_prefix} #{r.version} #{r.alias_suffix}\n"
              end
            end
          end
        end

        def dependency_descriptor
          if type == 'compilers'
            # compilers have no dependencies
            %Q(set dependencies "")
          else
            depends = requirements.map do |r|
              case r.type
              when 'compilers'
                "[alces pretty #{r.path.gsub(/^compilers\//,'libs/')}] (using: [alces pretty [search #{r.compiler_libs_alias_prefix} #{r.version} #{r.alias_suffix}]])"
              else
                "[alces pretty #{r.path}] (using: [alces pretty [search #{r.alias_prefix} #{r.version} #{r.alias_suffix}]])"
              end
            end
            dependencies = case depends.length
                           when 0 
                             nil
                           when 1 
                             "     Dependencies: #{depends.first}"
                           else
                             "     Dependencies: #{depends.shift}".tap do |s|
                               depends.each { |d| s << "\n#{" " * 19}#{d}" }
                             end
                           end
            %Q(if { [ namespace exists alces ] } { set dependencies "#{dependencies}" } { set dependencies "" })
          end
        end

        def whatis
          compiler = (c = requirements.find { |r| r.type == 'compilers' }) && "[alces pretty #{c.path}]" || 'N/A'
          # build args - ie. which modules were used during
          # build, which params were specified (variant already in app
          # name, so that doesn't need to be reiterated)
          build_args = [].tap do |a|
            a << "    Build modules: #{modules}" if modules != ""
            a << " Build parameters: #{params}" if params != ""
          end.join("\n")
          build_args = build_args + "\n" if build_args != ""
          <<-EOF


            Title: #{metadata.title}
          Summary: #{metadata.summary}
          License: #{metadata.license}
            Group: #{metadata.group}
              URL: #{metadata.url}

             Name: #{name}
          Version: #{version}
           Module: [alces pretty #{package.path}]
      Module path: #{modulefile_path}
     Package path: #{package_dir}

       Repository: #{(repo = metadata.repo) ? repo.descriptor : 'N/A'}
          Package: #{metadata.source_descriptor}
      Last update: #{metadata.date}

          Builder: #{builder}
       Build date: #{Time.now.strftime('%Y-%m-%dT%H:%M:%S')}
#{build_args}         Compiler: #{compiler}
#{compiler == 'N/A' ? nil : build_details}$dependencies

For further information, execute:

\tmodule help #{package.path}
EOF
        end

        def builder
          me = `whoami`.chomp
          "#{me}@#{`hostname -f`.chomp}".tap do |s|
            gecos = Etc.getpwnam(me)['gecos']
            s << " (#{gecos})" unless gecos.nil? || gecos == "" || gecos == me
          end
        end

        def build_details
          cpu_details = case `uname -s`.chomp
                        when 'Linux'
                          {
                           model: `grep 'model name' /proc/cpuinfo | head -n1 | awk -F: '{ print $2 }'`.strip.gsub(/\s\s+/,' '),
                           cpus: `grep 'physical id' /proc/cpuinfo | sort | uniq | wc -l`.chomp,
                           cores: `grep 'cpu cores' /proc/cpuinfo | head -n1 | awk -F: '{ print $2 }'`.strip,
                           identifier: Digest::MD5.hexdigest(IO.popen('cat /proc/cpuinfo | egrep -v "bogomips|cpu MHz"'){|io|io.read})
                          }
                        when 'Darwin'
                          {
                           model: `sysctl -n machdep.cpu.brand_string`.strip,
                           cpus: 1, # XXX
                           cores: `sysctl -n machdep.cpu.core_count`.strip
                          }.tap { |h| h[:identifier] = Digest::MD5.hexdigest("#{h[:model]}:#{h[:core_count]}") }
                        end
          arch = "#{cpu_details[:model] || 'Unknown'}".tap do |s|
            s << ", #{cpu_details[:cpus]}x#{cpu_details[:cores]}" if cpu_details[:cpus]
            s << " (#{cpu_details[:identifier][0..7]})" if cpu_details[:identifier]
          end
          <<-EOF
           System: #{`uname -msr`.chomp}
             Arch: #{arch}
          EOF
        end

        def modulefiles
          { (p = modulefile_name) => render_modulefile(p) }
        end

        def modulefile_name
          [type, name, version, tag].compact.join('/')
        end
        
        def render_modulefile(path)
          ERB.new(template).result(binding)
        end

        def template
          File.read(template_path(type))
        end

        def template_path(type)
          File.join(File.dirname(__FILE__), 'templates', "#{type}.erb")
        end
      end

      class CompilerModuleFileRenderer < ModuleFileRenderer
        # compilers have two modulefiles; one for using the
        # compiler and one for setting up the environment for
        # compiled libraries/applications for shared libraries
        # etc.
        def modulefiles
          super.merge( (p = library_modulefile_name) => render_library_modulefile(p, library_specifics) )
        end

        def package_specifics
          metadata.module_content[:compiler] rescue nil
        end

        def library_specifics
          metadata.module_content[:runtime] rescue nil
        end

        def library_modulefile_name
          ['libs', name, version, tag].compact.join('/')
        end
        
        def render_library_modulefile(path, package_specifics)
          ERB.new(library_template).result(binding)
        end

        def library_template
          File.read(template_path('compiler-libs'))
        end
      end
    end
    Dao.finalize!
  end
end
