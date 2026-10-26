# socket_stub.rb
# The Switch libruby has no socket extension. This offline stand-in lets games
# that `require 'socket'` at load time (e.g. the Essentials Cable Club plugin)
# start; any connection attempt fails like an unreachable server.

unless defined?(TCPSocket)
	class SocketError < StandardError; end

	class TCPSocket
		def self.open(host, port, *args)
			raise Errno::ECONNREFUSED, "networking is unavailable on Switch (#{host}:#{port})"
		end

		def self.new(host, port, *args)
			return open(host, port, *args)
		end
	end

	$LOADED_FEATURES << "socket.rb"
end
