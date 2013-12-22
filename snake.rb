#!/usr/bin/env ruby

require 'socket'
require 'gosu'
require 'thread'

$WIDTH = 641
$HEIGHT = 481
$BOX_SIZE = 20

$NUM_X = $WIDTH / $BOX_SIZE
$NUM_Y = $HEIGHT / $BOX_SIZE

module DIRECTION
	NORTH = 1
	EAST  = 2
	SOUTH = 3
	WEST  = 4
end

class SnakeWorld
	attr_accessor:snakes
	attr_accessor:fruits
	attr_accessor:grid_height
	attr_accessor:grid_width
	attr_accessor:num_players
	def initialize
		@fruits = []
		@snakes = []
		@grid_width = $NUM_X
		@grid_height = $NUM_Y
		@num_players = 0
		@desired_num_fruits = 1
	end
	
	def tick
		@snakes.each { |snake|
			snake.move(fruits, grid_width, grid_height)
		}
		@snakes.each { |snake|
			snake.check_snakes_collision(snakes)

		}
		@snakes.each { |snake|
			if snake.dead
				return true
			end
		}
		if @desired_num_fruits > fruits.length then
			fruits.insert(-1, [rand(0...@grid_width), rand(0...@grid_height)])
		end
		return false
	end
	
	def turn(player, dir)
		if(player < @num_players and player >= 0) then
			@snakes[player].turn(dir)
		end
	end
	
	def spawn_fruit(x,y)
		fruits.insert(-1, [x,y])
	end
	
end

class Snake
	attr_accessor:location
	attr_accessor:x_vel
	attr_accessor:y_vel
	attr_accessor:dead
	attr_accessor:player_id
	def initialize(x,y,player)
		@location = [[x,y]]
		@x_vel = 1
		@y_vel = 0
		@new_dir = 0
		@dead = false
		@player_id = player
	end
	
	def grow
		@location.insert(0, [-1,-1])
	end
	
	def do_turn(dir)
		if (dir % 2) == 0
			if @x_vel != 0
				return
			end
			@x_vel = (dir == 2) ? 1 : -1
			@y_vel = 0
		else
			if @y_vel != 0
				return
			end
			@x_vel = 0
			@y_vel = (dir == 1) ? -1 : 1
		end
	end
	
	def check_snakes_collision(snakes)
		snakes.each { |sn|
			if sn.player_id != @player_id then
				sn.location.each { |loc|
					if loc[0] == @location[-1][0] and loc[1] == @location[-1][1] then @dead = true end
				}
			end
		}
	end
	
	def move(fruits, width, height)
		do_turn(@new_dir)
		(1..(@location.length-1)).each { |n|
			@location[n-1][0] = @location[n][0]
			@location[n-1][1] = @location[n][1]
		}
		die = false
		@location[-1][0] += x_vel
		@location[-1][1] += y_vel
		if @location[-1][0] >= width then die = true end
		if @location[-1][1] >= height then die = true end
		if @location[-1][0] < 0 then die = true end
		if @location[-1][1] < 0 then die = true end
		
		if(@location.length >= 2)
			(0...(@location.length-1)).each { |n|
				if @location[-1][0] == @location[n][0] and @location[-1][1] == @location[n][1] then die = true end
			}
		end
		
		if die == false 
			fruits.each { |f|
				if f[0] == @location[-1][0] and f[1] == @location[-1][1]
					grow
					fruits.delete(f)
				end
			}
		end
		@dead = die
	end
	
	def turn(dir)
		@new_dir = dir
	end
	
end

class SnakeServer
	def initialize
		@world = SnakeWorld.new()
		@tick = 0
		@speed_modulus = 10
		@game_running = false
		@num_players = 0
		@socket = TCPServer.open(1025)
		@world.snakes[0] = Snake.new(1,1,0)
		@world.snakes[0].grow
		@world.num_players = 1
		@data = ""
		@lock = Mutex.new
		@ready_threads = 0
		@max_players = 1
	end
	
	def talk_to_client(client)
		@num_players += 1
		con = client.recv(32)
		puts ":: #{con}"
		
		while !(client.closed?)
			if (@data <=> "") != 0 then
				client.send(@data, 0)
				@lock.synchronize {
					@ready_threads += 1
				}
			else
				begin
					cmd = client.recv_nonblock(32)
					case cmd[0]
					when 'n'
						@world.turn(0, DIRECTION::NORTH)
					when 's'
						@world.turn(0, DIRECTION::SOUTH)
					when 'e'
						@world.turn(0, DIRECTION::EAST)
					when 'w'
						@world.turn(0, DIRECTION::WEST)
					end
				rescue
				end
			end
			sleep 0.01
		end
	end
	
	def server_loop
		Thread.start {
			while @num_players < @max_players
				Thread.start(@socket.accept) do |client|
					puts "accepting connection to client (#{client})"
					talk_to_client(client)
				end
			end
		}
		while @num_players < @max_players
			sleep 0.1
		end
		puts "Maximum players connected, starting game"
		loop {
			sleep 0.1
			@world.tick
			@lock.synchronize {
				str = ""
				@world.snakes.each { |snake|
					snake.location.each { |loc|
						str += "#{loc[0]},#{loc[1]},s;"
					}
				}
				@world.fruits.each { |fruit|
					str += "#{fruit[0]},#{fruit[1]},f;"
				}
				@data = str
			}
			
			while @ready_threads < @num_players
				sleep 0.0000001
			end
			
			@data = ""
			@ready_threads = 0
			
		}
	end
	
end

class GameWindow < Gosu::Window
	def initialize
		super $WIDTH, $HEIGHT, false
		self.caption = "Snake"
		@font = Gosu::Font.new(self, Gosu::default_font_name, 20)
		
		@server = TCPSocket.new("localhost", 1025)
		@server.send("join", 0)
		@locs = []
	end
	
	def update
		begin
			str = @server.recv_nonblock(1024)
			@locs = str.split(";")
		rescue IO::WaitReadable
		end
	end
	
	def button_down(id)
		case id
			when Gosu::KbLeft
				@server.send("w",0)
			when Gosu::KbRight
				@server.send("e",0)
			when Gosu::KbUp
				@server.send("n",0)
			when Gosu::KbDown
				@server.send("s",0)
				
			when Gosu::KbA
				@world.turn(1, DIRECTION::WEST)
			when Gosu::KbD
				@world.turn(1, DIRECTION::EAST)
			when Gosu::KbW
				@world.turn(1, DIRECTION::NORTH)
			when Gosu::KbS
				@world.turn(1, DIRECTION::SOUTH)
		end
	end

	def fill_square(x, y, col)
		xoff = x * ($BOX_SIZE) + 4
		yoff = y * ($BOX_SIZE) + 4
		draw_quad(xoff, yoff, col, xoff + ($BOX_SIZE-7), yoff, col, xoff + ($BOX_SIZE-7), yoff + ($BOX_SIZE-7), col, xoff, yoff + ($BOX_SIZE-7), col)
	end
	
	def draw
		if @game_running == false
			@font.draw("Snake (press escape to start)", 10, 10, 0, 1.0, 1.0, 0xffffff00)
			r=0
			return
		end
		for i in 0..$WIDTH/$BOX_SIZE
			draw_line(i * $BOX_SIZE+1,0,0x77777777,i * $BOX_SIZE,$HEIGHT,0x77777777);
		end
		for i in 0..$HEIGHT/$BOX_SIZE
			draw_line(0, i * $BOX_SIZE+1,0x77777777,$WIDTH,i * $BOX_SIZE,0x77777777);
		end
		@locs.each { |l|
			col = 0xffffffff
			arr = l.split(",")
			case arr[2]
			when "f"
				col = 0xff4444ff
			when "s"
				col = 0xffff0000
			end
			fill_square(arr[0].to_i,arr[1].to_i,col)
		}
		
		#@world.fruits.each { |f|
		#	fill_square(f[0], f[1], 0xff4444ff)
		#}
		#@world.snakes.each { |sn|
		#	sn.location.each { |pos|
		#		if !(pos[1] == -1 or pos[0] == -1)
		#			fill_square(pos[0], pos[1], 0xffff0000)
		#		end
		#	}
		#}
	end
end
$stdout.sync = true
server = SnakeServer.new

Thread.start() do
	server.server_loop
end

window = GameWindow.new
window.show
