-- Description: breakout game component
-- FSM-based design 

-- Engineer: Sean Breen & Dara Golden, National University of Ireland, Galway
-- Date: 16/11/2022
-- 
-- 16 x 32-bit game array, using reg32x32(15 downto 0)(31:0)

-- On completion
--    write reg4x32_CSRA(0)(1:0)  = 0b10, i.e, (1) = 1 => FPGA done, (0) = 0 => return control to host. Other CSRA(0) bits unchanged
--
-- Signal dictionary
--  clk					system clock strobe, rising edge active
--  rst	        		assertion (h) asynchronously clears all registers
--  ce                  chip enable, asserted high                 		 
--  go			        Assertion (H) detected in idle state to active threshold function 
--  active (Output)     Default asserted (h), except in idle state

--  reg4x32_CSRA    	4 x 32-bit Control & Status registers, CSRA
--  reg4x32_CSRB      	32-bit Control register, CSRB
--  BRAM_dOut	        Current source memory 256-bit data (not used in this application)

--  wr  (Output)        Asserted to synchronously write to addressed memory
--  add (Output)  	    Addressed memory - 0b00100000 to read BRAM(255:0)
--  datToMem (Output)   32-bit data to addressed memory 

--  functBus            96-bit array of function signals, for use in debug and demonstration of function behaviour 
--  			        Not used in this example

-- Internal Signal dictionary
--  NS, CS                         finite state machine state signals 
--  NS*, CS* 				       next and current state signals 

--    Using integer types for INTERNAL address signals where possible, to make VHDL model more readable

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.arrayPackage.all;

entity game is
    Port ( clk 		     : in STD_LOGIC;   
           rst 		     : in STD_LOGIC; 
           ce            : in  std_logic;                		 
           go            : in  std_logic;                		 
		   active        : out std_logic;

		   reg4x32_CSRA  : in array4x32; 
		   reg4x32_CSRB  : in array4x32;	
           BRAM_dOut     : in std_logic_vector(255 downto 0);	
           reg32x32_dOut : in std_logic_vector(31 downto 0);
					 
		   wr            : out std_logic;
		   add           : out std_logic_vector(  7 downto 0);					 
		   datToMem	     : out std_logic_vector( 31 downto 0);

		   functBus      : out std_logic_vector(95 downto 0)
           );
end game;

architecture RTL of game is
-- Internal signal declarations
-- <include new states>
type stateType is (idle, writeToCSR0, setupGameParameters, initGameArena, initBall, initPaddle, initLives, initScore, waitState, processPaddle, processBall, writeBallToMem, endGame, updateWall, updateLives, updateScore, resetPaddle, resetBall); -- declare enumerated state type
signal NS, CS                                   : stateType; -- declare FSM state 
								                
signal NSWallVec, CSWallVec                     : std_logic_vector(31 downto 0);
signal NSBallVec, CSBallVec                     : std_logic_vector(31 downto 0);
signal NSPaddleVec, CSPaddleVec                 : std_logic_vector(31 downto 0);
								                
signal NSBallXAdd, CSBallXAdd                   : integer range 0 to 31;
signal NSBallYAdd, CSBallYAdd                   : integer range 0 to 31;
signal NSBallDir, CSBallDir                     : std_logic_vector(2 downto 0);
								                
signal NSScore, CSScore                         : integer range 0 to 31;
signal NSLives, CSLives                         : integer range 0 to 31;

-- Clock frequency = 12.5MHz, count 0 - 12,499,999 to create 1 second delay 
-- 100ms delay => count ~ 0 - 1,250,000
signal NSDlyCountMax, CSDlyCountMax             : integer range 0 to 1250000;
signal NSDlyCount, CSDlyCount                   : integer range 0 to 1250000;

signal NSPaddleNumDlyMax, CSPaddleNumDlyMax     : integer range 0 to 31;
signal NSPaddleNumDlyCount, CSPaddleNumDlyCount : integer range 0 to 31;

signal NSBallNumDlyMax, CSBallNumDlyMax         : integer range 0 to 31;
signal NSBallNumDlyCount, CSBallNumDlyCount     : integer range 0 to 31;

signal zone 									: integer; 

signal NSPaddleLSB, CSPaddleLSB					: integer range 0 to 27; --least significant bit of paddle - can be used to determine which bit of paddle was hit
																		 --initially would be 13 when game started
signal NSResetFlag, CSResetFlag				    : integer range 0 to 1;
begin

asgnFunctBus2_i: functBus <= (others => '0'); -- not currently used 

-- FSM next state and o/p decode process
-- <include new signals in sensitivity list>
NSAndOPDec_i: process (CS, go, 
					   reg4x32_CSRA, reg4x32_CSRB, reg32x32_dOut, 
					   CSWallVec, CSPaddleVec, CSBallXAdd, CSBallYAdd, CSBallDir, CSScore, CSLives, 
					   CSDlyCountMax, CSPaddleNumDlyMax, CSBallNumDlyMax, CSDlyCount, CSPaddleNumDlyCount, CSBallNumDlyCount,
					   CSPaddleLSB, CSResetFlag)
begin
   NS 	 		       <= CS;     -- default signal assignments
   NSWallVec           <= CSWallVec;
   NSBallVec           <= CSBallVec;
   NSPaddleVec         <= CSPaddleVec;
   NSBallXAdd          <= CSBallXAdd;
   NSBallYAdd          <= CSBallYAdd;
   NSBallDir           <= CSBallDir;
   NSScore             <= CSScore;
   NSLives             <= CSLives;
   NSDlyCount          <= CSDlyCount;           
   NSPaddleNumDlyCount <= CSPaddleNumDlyCount;
   NSBallNumDlyCount   <= CSBallNumDlyCount; 
   NSDlyCountMax       <= CSDlyCountMax;
   NSDlyCount          <= CSDlyCount;
   NSPaddleNumDlyMax   <= CSPaddleNumDlyMax;
   NSBallNumDlyMax     <= CSBallNumDlyMax;
   active    	       <= '1';             -- default asserted. Deasserted only in idle state. 
   wr   	           <= '0';
   add	               <= "010" & "00000"; -- reg32x32 base address
   datToMem            <= (others => '0');
   zone                <= 0;
   
   NSPaddleLSB		   <= CSPaddleLSB;	--added these signals
   NSResetFlag		   <= CSResetFlag;

  case CS is 
		when idle => 			     
			active  <= '0';  
            if go = '1' then 
				if    reg4x32_CSRA(0)(10 downto 8) = "000" then -- initialise game values and progress to init game arena states 
					NS 					<= setupGameParameters;							
				elsif reg4x32_CSRA(0)(10 downto 8) = "001" then -- play game
					NSDlyCount          <= 0;                   -- clear delay counters  
					NSPaddleNumDlyCount <= 0;  
					NSBallNumDlyCount   <= 0;
					NS                  <= waitState;
				end if;
			end if;

		when writeToCSR0 =>                                        -- finish. Return done state and return control to host
			wr       <= '1';
            add      <= "000" & "00000"; 						   -- reg4x32_CSRA address = 0 
		    datToMem <=   reg4x32_CSRA(0)(31 downto  8)            -- bits unchanged 
                        & reg4x32_CSRA(0)( 7 downto  2) & "10";    -- byte 0, bit(1) = 1 => FPGA done, bit(0) = 0 => return control to host. Bits 7:2 unchanged
			NS       <= idle;


		when setupGameParameters =>  
			NSWallVec           <= reg4x32_CSRA(3);
			NSBallXAdd 	        <= to_integer( unsigned(reg4x32_CSRA(2)(28 downto 24)) );
			NSBallYAdd 	        <= to_integer( unsigned(reg4x32_CSRA(2)(20 downto 16)) );
			NSLives             <= to_integer( unsigned(reg4x32_CSRA(2)( 3 downto  0)) );
			NSScore             <= to_integer( unsigned(reg4x32_CSRA(2)( 7 downto  4)) );        --change to 8 from 7 if want to input score of 30 for testing
			NSBallVec           <= reg4x32_CSRA(1);

			NSPaddleVec         <= reg4x32_CSRB(3);
			NSBallDir           <= reg4x32_CSRB(2)(26 downto  24);
			NSDlyCountMax       <= to_integer( unsigned(reg4x32_CSRB(2)(19 downto  0)) );                 
			NSPaddleNumDlyMax   <= to_integer( unsigned(reg4x32_CSRB(1)(28 downto 24)) );
			NSBallNumDlyMax     <= to_integer( unsigned(reg4x32_CSRB(1)(20 downto 16)) );
			NS                  <= initGameArena;

		when initGameArena => -- follow an initialisation sequence
            -- write wallVec
			wr   	      <= '1';
			add           <= "010" & "01111";               -- reg32x32 row 15
			datToMem      <= CSWallVec;
           	NS            <= initBall;
			
			NSResetFlag   <= 0;		--added this
			
		when initBall => 
			wr   	      <= '1';
			add	          <= "010" & std_logic_vector( to_unsigned(CSBallYAdd,5) );  
			datToMem      <= CSBallVec;
           	NS            <= initPaddle;
		when initPaddle =>
			wr   	      <= '1';
			add	          <= "010" & "00010";               -- reg32x32 row 2 
			datToMem      <= CSPaddleVec;
           	NS            <= initLives;
			
			NSPaddleLSB   <= 13;			--added this
			
		when initLives =>                          
			wr   	      <= '1';
			add	          <= "010" & "00001";               -- reg32x32 row 1
			datToMem      <= X"000000" & "000" & std_logic_vector( to_unsigned(CSLives, 5) );  
           	NS            <= initScore;     
		when initScore =>                          
			wr   	      <= '1';
			add	          <= "010" & "00000";               -- reg32x32 row 0 
			datToMem      <= X"000000" & "000" & std_logic_vector( to_unsigned(CSScore, 5) );  
           	NS            <= writeToCSR0;                   -- finish. Return done state and return control to host


		when waitState =>                                   -- increment count and loop in state until value reaches delay value       
			if CSDlyCount = CSDlyCountMax then
	     	    NSDlyCount <= 0;                            -- clear delay counter and process paddle and/or ball	     	         	    
   	   	        NS  <= processPaddle;
            else
	   	        NSDlyCount    <= CSDlyCount + 1;                
			end if;
			
	     	    			
        -- read reg4x32_CSRA(0)(9:8) and move paddle left / right, between boundaries
		when processPaddle =>                               -- read CSRB(0)(9:8)
			if CSPaddleNumDlyCount = CSPaddleNumDlyMax then
	     	   NSPaddleNumDlyCount <= 0;                    -- clear counter
		       add	<= "010" & "00010";                     -- reg32x32 row 2 (paddle row) 
			     if reg4x32_CSRB(0)(9) = '1' then           -- shift paddle left, if not at bit 31 boundary
			        if reg32x32_dOut(31) = '0' then 
				        wr   	      <= '1';
					    add	          <= "010" & "00010";   -- reg32x32 row 2, paddle row address 
					    datToMem      <= reg32x32_dOut(30 downto 0) & '0';

						NSPaddleLSB	  <= CSPaddleLSB + 1;		--updating LSB value on successful paddle moves to ensure bouncing behaviour is accurate to what is desired						
						
				    end if;
			      elsif reg4x32_CSRB(0)(8) = '1' then       -- shift paddle right, if not at bit 0 boundary 
			        if reg32x32_dOut(0) = '0' then 
					    wr   	      <= '1';
					    add	          <= "010" & "00010";   -- reg32x32 row 2, paddle row address 
					    datToMem      <= '0' & reg32x32_dOut(31 downto 1); 
						
						NSPaddleLSB	  <= CSPaddleLSB - 1;		--updating LSB value on successful paddle moves to ensure bouncing behaviour is accurate to what is desired
						
				    end if;
				  end if;   		  
           	else
	           NSPaddleNumDlyCount <= CSPaddleNumDlyCount + 1; -- increment counter
           	   NS  <= processBall;
           	end if;		

		-- ========= Only partially completed =========
        when processBall => 	
			if CSBallNumDlyCount = CSBallNumDlyMax then
		   	   NSBallNumDlyCount   <= 0;


               -- < instructions>		      
			   -- Perform ball zone checks with respect to boundaries, wall, paddle. 
			   -- Assign signal zone, for reference only
		       -- Update ball X/Y, directon, score, lives, wall. 
		       -- Check if end game
	 	       -- loop to waitState or progress to endGame
		
			   -- Check if ZoneCentral Y4To13_X1To30, up or down  
			   if CSBallYAdd >= 4 and CSBallYAdd <= 13 and CSBallXAdd >= 1 and CSBallXAdd <= 30 then  
			      zone <= 1;
				  if CSBallDir(2) = '1' then                        -- ball direction is up                               -- ball direction is up?
			         NSBallYAdd                  <= CSBallYAdd + 1; -- move up in Y direction
                     case CSBallDir(1 downto 0) is                                               -- 00 no CSBallXAdd change, 11 not valid, will not occur
                       when "01"   => NSBallXAdd <= CSBallXAdd - 1;                              -- if NE, decrement NSBallXAdd, moving east 
                       when "10"   => NSBallXAdd <= CSBallXAdd + 1;                              -- if NW, increment XAdd, moving west 
                       when others => null;                                                      -- no change
                     end case;                                                           
			       else  						                    -- ball direction is down                             -- ball direction is down?
			         NSBallYAdd                  <= CSBallYAdd - 1;                              -- move down in Y direction		 
                     case CSBallDir(1 downto 0) is                                               -- 00 no CSBallXAdd change, 11 not valid, will not occur
                       when "01"   => NSBallXAdd <= CSBallXAdd - 1;                              -- if SE, decrement NSBallXAdd, moving east 
                       when "10"   => NSBallXAdd <= CSBallXAdd + 1;                              -- if SW, increment NSBallXAdd, moving west 
                       when others => null; 									                 -- no change
                     end case;
			       end if;

			   
			   --LEFT SIDE MIDDLE CASE
			   elsif CSBallYAdd >=4 and CSBallYAdd <= 13 and CSBallXAdd = 31 then			--use the key in powerpoint to know what the numbers should be here
					 zone <= 2;
					 if CSBallDir(2) = '1' then						
						NSBallYAdd					<= CSBallYAdd + 1;
						case CSBallDir(1 downto 0) is
							when "01" => NSBallXAdd <= CSBallXAdd - 1;		--this shouldnt occur normally 
							when "10" => NSBallXAdd <= CSBallXAdd - 1; NSBallDir <= "101";						--10 west 01 east
							when others => null;							--Bit before determines up down
						end case;
					 else 	
						NSBallYAdd					<= CSBallYAdd - 1;
						case CSBallDir(1 downto 0) is
							when "01" => NSBallXAdd <= CSBallXAdd - 1;
							when "10" => NSBallXAdd <= CSBallXAdd - 1; NSBallDir <= "001";
							when others => null;
						end case;
					 end if;
					
			   --RIGHT SIDE MIDDLE CASE
			   elsif CSBallYAdd >= 4 and CSBallYAdd <= 13 and CSBallXAdd = 0 then
					 zone <= 3;
					 if CSBallDir(2) = '1' then --up direction
						NSBallYAdd					<= CSBallYAdd + 1;
						case CSBallDir(1 downto 0) is 
							when "01" => NSBallXAdd <= CSBallXAdd + 1; NSBallDir <= "110";
							when "10" => NSBallXAdd <= CSBallXAdd + 1; --this scenario shouldn't occur during normal operation
							when others => null;
						end case;
					 else	--down direction
						NSBallYAdd					<= CSBallYAdd - 1;
						case CSBallDir(1 downto 0) is 
							when "01" => NSBallXAdd <= CSBallXAdd + 1; NSBallDir <= "010";
							when "10" => NSBallXAdd <= CSBallXAdd + 1; --this scenario shouldn't occor during normal operation
							when others => null;
						end case;

					 end if;
			   
			   	
			   
			   --BOTTOM ROW MIDDLE CASE 
			   elsif CSBallYAdd = 3 and CSBallXAdd <= 30 and CSBallXAdd >= 1 then
					 zone <= 4;
					 if CSBallDir(2) = '1' then --ball going up, no need to consider bounce off paddle characteristics here
						NSBallYAdd 					<= CSBallYAdd + 1;
						case CSBallDir(1 downto 0) is
							when "01" => NSBallXAdd <= CSBallXAdd - 1;
							when "10" => NSBallXAdd <= CSBallXAdd + 1;
							when others => null;
						end case;
						
					 else			 --going down, have to worry about if paddle present, if yes do bounce, if no, decrement life
							
						if  (CSBallXAdd - CSPaddleLSB) = 0 then		--hit right side of paddle, bounce NE 
							NSBallDir <= "101";
							NSBallXAdd <= CSBallXAdd - 1;
							NSBallYAdd <= CSBallYAdd + 1;
						
						elsif (CSBallXAdd - CSPaddleLSB) > 0 and (CSBallXAdd - CSPaddleLSB) < 4 then 	--hit middle 3 pieces of paddle, go straight up
							NSBallDir <= "100";						--straight upwards
							NSBallYAdd <= CSBallYAdd + 1;
																	--XAdd stays the same as we are now going straight up
							
						elsif (CSBallXAdd - CSPaddleLSB) = 4 then 	--hit left side of paddle, bounce NW
							NSBallDir <= "110";						
							NSBallXAdd <= CSBallXAdd + 1;
							NSBallYAdd <= CSBallYAdd + 1;
							
						else	--missed, no paddle present, decrement lives, reset ball and paddle if sufficient lives still available
							
							NSLives    <= CSLives - 1;
							NSResetFlag <= 1;	--assert reset flag so game knows it must reset ball and paddle next
							--
							--NSBallXAdd <= 16;	--just hard coding reset at the minute, maybe shouldn't will review, just get functional for nows
							--NSBallYAdd <= 3;
							--NSBallDir  <= "100";		--moving straight up by default
						end if;
					 	
					 end if;
					 
			   --BOTTOM LEFT CORNER CASE	 
			   elsif CSBallYAdd = 3 and CSBallXAdd = 31 then		
					 zone <= 99;		--decide on zone numbers
					 if CSBallDir(2) = '1' then --ball going up, don't need to worry about it 
						NSBallYAdd 					<= CSBallYAdd + 1;
						case CSBallDir(1 downto 0) is
							when "01" => NSBallXAdd <= CSBallXAdd - 1;		--may need to make changes here, will look into, to do with making sure ball reflects properly
							when "10" => NSBallXAdd <= CSBallXAdd + 1;
							when others => null;
						end case;
					
					 else
						if (CSBallXAdd - CSPaddleLSB) = 4 then 	--hit left side of paddle, only condition possible here
							NSBallDir  <= "101";
							NSBallXAdd <= CSBallXAdd - 1;
							NSBallYAdd <= CSBallYAdd + 1;
							
						else	--missed, no paddle present, begin looking at life decrement and resetting ball where lives still available
							NSLives    <= CSLives - 1;	
							NSResetFlag <= 1;	--assert reset flag so game knows it must reset ball and paddle next



							--NSBallXAdd <= 16;	--just hard coding reset at the minute, maybe shouldn't will review, just get functional for nows
							--NSBallYAdd <= 3;
							--NSBallDir  <= "100";		--moving straight up by default
						end if;
					 	
					 end if;
			   --BOTTOM RIGHT CORNER CASE 	 
			   elsif CSBallYAdd = 3 and CSBallXAdd = 0 then		
					 zone <= 109;		--decide on zone numbers
					 if CSBallDir(2) = '1' then --ball going up, don't need to worry about it 
						NSBallYAdd 					<= CSBallYAdd + 1;
						case CSBallDir(1 downto 0) is
							when "01" => NSBallXAdd <= CSBallXAdd - 1;
							when "10" => NSBallXAdd <= CSBallXAdd + 1;
							when others => null;
						end case;
						
						
						
					 else
						if (CSBallXAdd - CSPaddleLSB) = 0 then 	--hit right side of paddle, only condition possible here
							NSBallDir <= "110";
							NSBallXAdd <= CSBallXAdd + 1;
							NSBallYAdd <= CSBallYAdd + 1;
							
						else	--missed, no paddle present, begin looking at life decrement and resetting ball where lives still available
							NSLives <= CSLives - 1;
							--reset ball and maybe paddle pieces here	
							NSResetFlag <= 1;	--assert reset flag so game knows it must reset ball and paddle next

							
							--NSBallXAdd <= 16;	--just hard coding reset at the minute, maybe shouldn't will review, just get functional for nows
							--NSBallYAdd <= 3;
							--NSBallDir  <= "100";		--moving straight up by default
						end if;
					 	
					 end if;
					 
			   --TOP ROW MIDDLE CASE 
			   elsif CSBallYAdd = 14 and CSBallXAdd <= 30 and CSBallXAdd >= 1 then
					 zone <= 5;
					 if CSBallDir(2) = '1' then 					--ball going up need to worry about erasing piece of wall if it is present
						NSBallYAdd 				<= CSBallYAdd - 1; 	--need to start sending ball downwards now
						NSBallDir 				<= "0" & CSBallDir(1 downto 0);	--keep same east west but change north south 
						
						--if row above has piece, remove and increment score, otherwise do nothing
						
						if CSWallVec( CSBallXAdd ) = '1' then	--bit present, remove and increment score
							NSwallVec(CSBallXAdd) <= '0';
							NSScore   <= CSScore + 1;
						--otherwise no wall present, don't need to worry about it
						end if;
						
						case CSBallDir(1 downto 0) is
							when "01" => NSBallXAdd <= CSBallXAdd - 1; 
							when "10" => NSBallXAdd <= CSBallXAdd + 1; 
							when others => null;	--no need to change X add if moving straight up
						end case;
					 else
						--no changes needed, already going down
						NSBallYAdd <= CSBallYAdd - 1;
						case CSBallDir(1 downto 0) is		
							when "01" => NSBallXAdd <= CSBallXAdd - 1; 
							when "10" => NSBallXAdd <= CSBallXAdd + 1; 
							when others => null;
						end case;
					 end if;
					 
			   --TOP LEFT CORNER CASE
		       elsif CSBallYAdd = 14 and CSBallXAdd = 31 then
					 zone <= 56;
					 if CSBallDir(2) = '1' then 					--ball going up need to worry about erasing piece of wall if it is present
						NSBallYAdd 				<= CSBallYAdd - 1; 	--need to start sending ball downwards now
						NSBallXAdd				<= CSBallXAdd - 1;
						NSBallDir 				<= "001";	--heading down and east
						
						--if row above has piece, remove and increment score, otherwise do nothing
						if CSWallVec(CSBallXAdd) = '1' then	--bit present, remove and increment score
							NSwallVec(CSBallXAdd) <= '0';
							NSScore  			  <= CSScore + 1;
						--otherwise no wall present, don't need to worry about it
						end if;
						
					 else
						--no changes needed, already going down
						NSBallYAdd <= CSBallYAdd - 1;
						case CSBallDir(1 downto 0) is		
							when "01" => NSBallXAdd <= CSBallXAdd - 1; 	--have to send ball east, otherwise gets stuck
							when "10" => NSBallXAdd <= CSBallXAdd - 1;  NSBallDir <= "001";
							when others => null;
						end case;
					 end if;
					 
					 
					 
					 --top right corner case
			   elsif CSBallYAdd = 14 and CSBallXAdd = 0 then
					 zone <= 57;
					 if CSBallDir(2) = '1' then 					--ball going up need to worry about erasing piece of wall if it is present
						NSBallYAdd 				<= CSBallYAdd - 1; 	--ball start moving downwards
						NSBallXAdd				<= CSBallXAdd + 1;
						NSBallDir 				<= "010";	
						
						if CSWallVec(CSBallXAdd) = '1' then	--bit present in wall row above, remove and increment score
							NSwallVec(CSBallXAdd) <= '0';
							NSScore  			  <= CSScore + 1;
																--else no wall present
						end if;
						
					 else
						--no changes needed, already going down
						NSBallYAdd <= CSBallYAdd - 1;
						case CSBallDir(1 downto 0) is		
							when "01" => NSBallXAdd <= CSBallXAdd + 1; 	NSBallDir <= "010";
							when "10" => NSBallXAdd <= CSBallXAdd + 1;   --have to send ball west, otherwise gets stuck
							when others => null;
						end case;
					 end if;

			   end if;	--have checked all  x and y addresses				   
			   
			   
		    wr                		  <= '1'; 					        			             -- clear current ball row
                  add(7 downto 5)     <= "010";                                                  -- reg32x32 memory bank select 
                  add(4 downto 0)     <= std_logic_vector( to_unsigned(CSBallYAdd, 5) );         -- current row address 
	   	          datToMem            <= (others => '0');							             -- clear row
		    NS          	          <= writeBallToMem;
			   
			  			   
           	else -- CSBallNumDlyCount != CSBallNumDlyMax 
	           NSBallNumDlyCount <= CSBallNumDlyCount + 1; -- increment counter
           	   NS  <= waitState;
           	end if;		
      
	  
			
		

		when writeBallToMem =>                                                           -- write new ball row
             wr                       <= '1'; 					        			      
             add(7 downto 5)          <= "010";                                          -- reg32x32 memory bank select 
             add(4 downto 0)          <= std_logic_vector( to_unsigned(CSBallYAdd, 5) ); -- row address
	   		 datToMem                 <= (others => '0');							     -- clear vector  
   	         datToMem( to_integer(to_unsigned(CSBallXAdd, 5)) ) <= '1';                  -- ball bit asserted
			 --NS <= waitState;
			 NS						  <= updateWall;
			 
			 if CSResetFlag = 1 then
				NSResetFlag <= 0;
				NS 			<= resetBall;		--
			 end if;
		
		--Added these 3 states to handle updating wall, lives and score in external memory
		
		when updateWall =>
			 wr                       <= '1'; 					        			      
             add(7 downto 5)          <= "010";                                          -- reg32x32 memory bank select 
             add(4 downto 0)          <= "01111";										 -- row address 15
	   		 datToMem                 <= (others => '0');							     -- clear vector  
   	         datToMem 				  <= CSWallVec;               					     -- refresh wall
			 NS                       <= updateLives;
			
		when updateLives =>
			 wr                       <= '1'; 					        			      
             add(7 downto 5)          <= "010";                                          -- reg32x32 memory bank select 
             add(4 downto 0)          <= "00001";										 -- row address 1
	   		 datToMem                 <= (others => '0');							     -- clear vector  
   	         datToMem 			      <= X"0000000" & std_logic_vector( to_unsigned(CSLives, 4) );              -- refresh Lives
			 NS                       <= updateScore;
			 
			 if CSLives = 0 then		--Checking to see if any lives remaining, if not end game 
			     NS <= endGame;
			 end if;
		
		when updateScore =>
			 wr                       <= '1'; 					        			      
             add(7 downto 5)          <= "010";                                          -- reg32x32 memory bank select 
             add(4 downto 0)          <= "00000";										 -- row address 0
	   		 datToMem                 <= (others => '0');							     -- clear vector  
   	         datToMem 				  <= X"000000" & std_logic_vector( to_unsigned(CSScore, 4) ) & X"0";        -- refresh score
			 NS                       <= waitState;
			 
			 if CSWallVec = X"00000000" then	--wall empty all pieces cleared
				NS <= endGame;					--have won the game + finished
			 end if;
		
		when resetBall =>
			 NSBallXAdd 			  <= 16;			--reset ball to default position after life loss
			 NSBallYAdd 			  <= 3;
			 NSBallDir  			  <= "100";		--moving straight up by default
			 NS         			  <= resetPaddle;

		when resetPaddle =>
			 wr                       <= '1'; 					        			      
             add(7 downto 5)          <= "010";                                          -- reg32x32 memory bank select 
             add(4 downto 0)          <= "00010";										 -- row address 1
	   		 datToMem                 <= (others => '0');							     -- clear vector  
   	         datToMem 			      <= reg4x32_CSRB(3);
			 NSPaddleLSB 			  <= 13;								--reset paddle LSB to maintain track of it accurately
			 NS                       <= waitState; 
		
		when endGame =>                          
			--write hex for dead over and over I'd say
		
			if CSLives = 0 then									 --game over have lost all lives
			wr                        <= '1';
            add(7 downto 5)           <="010";
            add(4 downto 0)           <="00001";    			 --need to change this to iterate thru each row in some way 
            datToMem                  <= (others => '0');
            datToMem                  <= X"00dead00"; 			
           	NS          			  <= writeToCSR0;            -- finish. Return done state and return control to host
			

			elsif CSWallVec = X"00000000" then --have won, victory screen
				wr                        <= '1';
				add(7 downto 5)           <="010";
				add(4 downto 0)           <="00001";    			 --need to change this to iterate thru each row
				datToMem                  <= (others => '0');
				datToMem                  <= X"c001c001"; 			 --update this to make it make more sense? 			
				NS           			  <= writeToCSR0;            -- finish. Return done state and return control to host
			end if;
			
		when others => 
			null;
	end case;
end process; 


-- Synchronous process registering current FSM state value, and other registered signals
-- registers include chip enable control
stateReg_i: process (clk, rst)
begin
  if rst = '1' then 		
    CS 	                <= idle;		
	CSWallVec           <= (others => '0');
	CSBallVec           <= (others => '0');
	CSPaddleVec         <= (others => '0');
    CSBallXAdd          <= 0;
    CSBallYAdd          <= 0;
    CSBallDir           <= (others => '0');
    CSScore             <= 0;
    CSLives             <= 0;
    CSDlyCount          <= 0;
    CSPaddleNumDlyCount <= 0;
    CSBallNumDlyCount   <= 0;
    CSDlyCountMax       <= 0;
    CSDlyCount          <= 0;
    CSPaddleNumDlyMax   <= 0;
	CSBallNumDlyMax     <= 0;
	CSResetFlag			<= 0;
	CSPaddleLSB			<= 0;
	
  elsif clk'event and clk = '1' then 
    if ce = '1' then
		CS 	                <= NS;		
		CSWallVec           <= NSWallVec;      
		CSBallVec           <= NSBallVec;      
		CSPaddleVec         <= NSPaddleVec;    
		CSBallXAdd          <= NSBallXAdd;     
		CSBallYAdd          <= NSBallYAdd;     
		CSBallDir           <= NSBallDir;      
		CSScore             <= NSScore;        
		CSLives             <= NSLives;        
		CSDlyCount          <= NSDlyCount;           
		CSPaddleNumDlyCount <= NSPaddleNumDlyCount;
		CSBallNumDlyCount   <= NSBallNumDlyCount; 
        CSDlyCountMax       <= NSDlyCountMax;
        CSDlyCount          <= NSDlyCount;
		CSPaddleNumDlyMax   <= NSPaddleNumDlyMax;
		CSBallNumDlyMax     <= NSBallNumDlyMax;
		CSPaddleLSB			<= NSPaddleLSB;
		CSResetFlag			<= NSResetFlag;
     end if;
  end if;
end process; 

end RTL;