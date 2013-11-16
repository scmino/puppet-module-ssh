# Management of SSH authorized_keys files from within Puppet.  See the docs
# embedded in the type (search for @doc) for details of how to use it.
#
# Copyright (C) 2007 Sol1 Pty Ltd
# Copyright (C) 2009,2013 Matt Palmer
#
# Authors: Christian Marie <christian@solutionsfirst.com.au>
#          Matt Palmer <mpalmer@hezmatt.org>
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
#

require 'fileutils'
require 'tempfile'
require 'etc'

module Puppet
	class Type
		module AuthorizedKey
			class SshKey
				attr_accessor :options, :type, :key, :comment, :user

				def initialize(str = nil)
					unless str.nil?
						@options = ""
						@type, wsp, rest = str.split(/(\s+)/, 2)
						until %w{ecdsa-sha2-nistp256 ecdsa-sha2-nistp384
						         ecdsa-sha2-nistp521 ssh-dss ssh-rsa}.include? @type or rest.nil?
							# The key type wasn't the key type, it was optionz!
							@options += @type + wsp
							@type, wsp, rest = rest.split(/(\s+)/, 2)
						end
						@options = @options.strip
						@options = nil if @options.empty?
						
						@key, @comment = rest.split(/\s+/, 2) unless rest.nil?
					end
				end
				
				def to_s
					if @options
						"#{@options} #{@type} #{@key} #{@comment}"
					else
						"#{@type} #{@key} #{@comment}"
					end
				end
				
				def valid?
					@type and @key
				end
				
				# Test for equality between two SshKey objects.  Two keys are
				# considered to be the same if they share the same values for
				# type and key (because two authorized_keys entries with the
				# same keydata will result in only the first entry being
				# examined).
				def ==(other)
					raise ArgumentError, "SshKey#== can only compare with other SshKeys (you provided a #{other.class})" unless other.is_a? SshKey
					
					 self.type == other.type and
					  self.key == other.key
				end
			end
		end
	end
			
	newtype :underscore_ssh_authorized_key do
		@doc = <<-EOD
			Manage authorized_keys files for users.
			
			The purpose of this type is just to make sure that entries are
			present or absent in an authorized_keys file in a user's home
			directory.  This is of use mainly when managing a "common" account
			that several people might have access to, such as a generic
			sysadmin account or file storage role account.
			
			In addition to specifying that certain keys must be present or
			absent, you can also tell the type that the authorized_keys file
			should only contain the keys that you explicitly define, and any
			other keys should be removed.  This is similar to the concept of
			"purging" provided in some other types (such as file).  The only
			difference is that with the authorized_keys type, the purging is
			controlled on a per-user basis, by a separate resource.  So if you
			want to enable purging for a user, use something like this:
			
			  authorized_key { read_my_lips:
			      user => johnny,
			      ensure => specified_only
			  }
			
			It's the "specified_only" that tells the type to purge unknown keys
			from the authorized_keys file for the given user.
		EOD

		# Oh... kay, then
		def self.instances
			@objects
		end

		newparam :name do
			desc "The name of the resource, also used as the comment on the key."

			isnamevar
		end
		
		newparam :options do
			desc "The options on the key."
		end
		
		newparam :user do
			desc "The user whose authorized_keys file we are managing."
		end

		newparam :type do
			desc "The ssh key type, e.g. 'ssh-dss'."
		end

		newparam :key do
			desc "The actual key data (the huge chunk of random characters).  For
			      cleanliness, we chomp whitespace off from around this, so you can
			      read your key data from a file without fear of insanity."
		end
		
		newproperty :ensure do
			desc "Whether the resource is in sync or not."
			defaultto :present

			# Take an AuthorizedKey resource object (or the current resource
			# if none is given) and turn it into an SshKey object (which is how
			# we represent these things internally, for ease of manipulation).
			#
			# If the resource that we're to convert isn't intended to be written
			# or removed (ie isn't ensure => present or ensure => absent) this
			# method will return nil, since the resource isn't an "SSH key" as
			# such.  It's a bit confusing, but it's the best I can do with the
			# current resource model.
			#
			def resource_as_ssh_key(r = nil)
				r = resource if r.nil?
				return nil unless r.should(:ensure) == :present or r.should(:ensure) == :absent
				k = ::Puppet::Type::AuthorizedKey::SshKey.new
				k.user = r[:user]
				k.options = r[:options].is_a?(Array) ? r[:options].join(',') : r[:options]
				if k.options == ""
					k.options = nil
				end
				k.type = r[:type]
				k.key = r[:key] ? r[:key].chomp : nil
				k.comment = r[:name]
				
				k
			end

			def ssh_dir
				File.expand_path "~#{resource[:user]}/.ssh"
			end

			def key_file
				File.join ssh_dir, 'authorized_keys'
			end

			def read_key_file
				begin
					lines = IO.readlines(key_file).select { |l| !(l =~ /^#/ or l.length < 10) }.map {|l| ::Puppet::Type::AuthorizedKey::SshKey.new(l.chomp) }.delete_if { |k| !k.valid? }
				rescue Errno::ENOENT
					lines = []
				end
			end

			def all_specified_keys
				res_list = []
				
				ObjectSpace.each_object(resource.class) do |res|
					res_list << resource_as_ssh_key(res)
				end
				res_list.compact.find_all do |r|
					# We only want the keys for this user
					r.user == resource[:user]
				end
			end

			def retrieve
				res = resource_as_ssh_key
				curr_state = :buggered_if_i_know
				
				if should == :specified_only
					begin
						key_list = read_key_file
					rescue Errno::ENOENT, Errno::ENOTDIR
						# There mustn't be any keys that need purging if there
						# aren't any keys at all!
						curr_state = :specified_only
					end
					
					key_list.delete_if { |k| all_specified_keys.find { |r| r == k } }
					
					key_list.each { |k| Puppet.info("Deleting key #{k.comment}") }
					curr_state = key_list.empty? ? :specified_only : :needs_purging
				else
					begin
						key_list = read_key_file
						curr_state = key_list.select { |k| k == res }.length > 0 ? :present : :absent
					rescue Errno::ENOENT, Errno::ENOTDIR
						# It's hard for a key to be present if there's no
						# authorized_keys file!
						curr_state = :absent
					end
				end
				curr_state
			end

			def update_key_file! &block
				FileUtils.mkdir_p ssh_dir
				key_list = yield read_key_file

				begin
					temp_file = key_file + ".#{$$.to_i}.#{rand}"

					File.open(temp_file, File::CREAT | File::WRONLY | File::EXCL, 0600) do |fd|
						fd.puts key_list.map {|k| k.to_s }.join("\n")
					end
					
					fmode, fuid, fgid = begin
						statinfo = File.stat(key_file)
						[statinfo.mode, statinfo.uid, statinfo.gid]
					rescue Errno::ENOENT
						[0440,
						 Etc.getpwnam(resource[:user]).uid,
						 Etc.getpwnam(resource[:user]).gid
						]
					end

					File.chmod fmode, temp_file
					File.chown fuid, fgid, temp_file
				rescue Errno::EEXIST
					# How did someone end up with the same tempfile?  Never mind,
					# we'll just try again
					retry
				end

				# Yay for race conditions!
				FileUtils.mv key_file, key_file + '~' if File.exists? key_file
				FileUtils.mv temp_file, key_file
			end

			newvalue :absent do
				update_key_file! do |key_list|
					res = resource_as_ssh_key
					key_list.delete_if { |k| k == res }
				end
			end

			newvalue :present do
				update_key_file! do |key_list|
					res = resource_as_ssh_key
					key_list << resource_as_ssh_key
				end
			end
			
			newvalue :specified_only do
				specified_list = all_specified_keys

				update_key_file! do |key_list|
					key_list.delete_if do |key|
						!specified_list.detect { |s| s == key }
					end
				end
			end
			
			newvalue :buggered_if_i_know do
				fail "You really shouldn't be asking me to go to this state."
			end
			
			newvalue :needs_purging do
				fail "You really shouldn't be asking me to go to this state."
			end
		end
	end
end
