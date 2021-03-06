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
require 'yaml'
require 'alces/tools/config'
module Alces
  module Packager
    module Config
      DEFAULT_CONFIG = {
        buildroot: '/usr/src/alces',
        gridware: '/opt/gridware'
      }

      class << self
        def config
          @config ||= DEFAULT_CONFIG.dup.tap do |h|
            cfgfile = Alces::Tools::Config.find("packager.#{ENV['alces_OS']}", false)
            h.merge!(YAML.load_file(cfgfile)) unless cfgfile.nil?
          end
        end

        def packages_dir
          if config[:packages_dir]
            File.expand_path(config[:packages_dir])
          else
            File.expand_path(Config.gridware)
          end
        end

        def modules_dir
          if config[:modules_dir]
            File.expand_path(config[:modules_dir])
          else
            File.expand_path(File.join(gridware,'modulefiles'))
          end
        end

        def method_missing(s,*a,&b)
          if config.has_key?(s)
            config[s]
          else
            super
          end
        end
      end
    end
  end
end

