-- Description: gameAndReg32x32_TB testbench 
-- Engineer: Fearghal Morgan
-- National University of Ireland, Galway / viciLogic 
-- Date: 8/2/2021
-- Change History: Initial version

-- The testbench does not write to CSRA, though controls signals wr, add and datToMem

-- Reference: https://tinyurl.com/vicilogicVHDLTips   	A: VHDL IEEE library source code VHDL code
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.arrayPackage.all;

entity gameAndReg32x32_TB is end gameAndReg32x32_TB; -- testbench has no inputs or outputs

architecture Behavioral of gameAndReg32x32_TB is
-- component declaration is in package

-- Declare internal testbench signals, typically the same as the component entity signals
-- initialise signal clk to logic '1' since the default std_logic type signal state is 'U' 
-- and process clkStim uses clk <= not clk  
signal clk            : STD_LOGIC := '1'; 
signal rst            : STD_LOGIC;
signal ce             : std_logic;
signal go             : STD_LOGIC;
signal active         : std_logic;

signal reg4x32_CSRA   : array4x32;
signal reg4x32_CSRB   : array4x32;
signal wr             : std_logic;
signal add            : std_logic_vector(  7 downto 0);		   
signal datToMem	      : STD_LOGIC_VECTOR( 31 downto 0);

signal functBus       : std_logic_vector(95 downto 0);

constant period       : time := 20 ns;    -- 50MHz clk
signal   endOfSim     : boolean := false; -- Default FALSE. Assigned TRUE at end of process stim
signal   testNo       : integer;          -- facilitates test numbers. Aids locating each simulation waveform test 

begin

uut: gameAndReg32x32
port map ( clk 		      => clk, 		 
           rst 		      => rst,
           ce             => ce, 		 
           go             => go,
		   active         => active,

		   reg4x32_CSRA   => reg4x32_CSRA,       
		   reg4x32_CSRB   => reg4x32_CSRB,       
						 
		   wr             => wr,
		   add            => add,    
		   datToMem	      => datToMem,
		   
		   functBus       => functBus	 
           );

-- clk stimulus continuing until all simulation stimulus have been applied (endOfSim TRUE)
clkStim : process (clk)
begin
  if endOfSim = false then
     clk <= not clk after period/2;
  end if;
end process;

stim: process -- no process sensitivity list to enable automatic process execution in the simulator
begin 
  report "%N : Simulation Start."; -- generate messages as the simulation executes 
  -- initialise all input signals   
  
  testNo <= 0; 					  -- include a unique test number to help browsing of the simulation waveform     
							      -- apply rst signal pattern, to deassert 0.2*period after the active clk edge
  go            		<= '0';   -- default assignments
  ce            		<= '1';
  reg4x32_CSRA          <= ( others => (others => '0') );        
  reg4x32_CSRB          <= ( others => (others => '0') );        
  rst    				<= '1';
  wait for 1.2 * period;
  rst    				<= '0';
  wait for 3*period;

-- ffffffff100403000001000000001000
  testNo 				<= 1; 
  reg4x32_CSRA                 <= ( others => (others => '0') ); -- clear all CSRA array         
  
  reg4x32_CSRA(3)              <= X"ffffffff";     -- wallVec 
  
  reg4x32_CSRA(2)(31 downto 24)<= "000" & "10000"; -- "000" & ballXAdd(4:0)      
  reg4x32_CSRA(2)(23 downto 16)<= "000" & "00100"; -- "000" & ballYAdd(4:0)      
  reg4x32_CSRA(2)(15 downto  8)<= "000" & "00011"; -- "000" & lives(4:0)      
  reg4x32_CSRA(2)( 7 downto  0)<= "000" & "00000"; -- "000" & score(4:0)      
  
 -- reg4x32_CSRA(2)(15 downto 8) <= X"00";
 -- reg4x32_CSRA(2)(7 downto 4)  <= "0000";		--score
 -- reg4x32_CSRA(2)(3 downto 0)  <= "0011";		--lives
  
  reg4x32_CSRA(1)              <= X"00010000";     -- ballVec 
  
  reg4x32_CSRA(0)(15 downto 8) <= "00010" & "000"; -- Initialise game. At top DPSProc level, (0) would also be asserted 
  
-- 0003e000040000020204000000000000
  reg4x32_CSRB                 <= ( others => (others => '0') ); -- clear all CSRA array         

  reg4x32_CSRB(3)              <= X"0003e000";     -- paddleVec  

  reg4x32_CSRB(2)(31 downto 24)<= "00000" & "100"; -- ball direction (2:0)   
  reg4x32_CSRB(2)(19 downto  0)<= X"00002";        -- dlyCount(19:0) 

  reg4x32_CSRB(1)(31 downto 24)<= "000" & "00010"; -- "000" & paddleNumDlyMax(4:0)      
  reg4x32_CSRB(1)(23 downto 16)<= "000" & "00100"; -- "000" & ballNumDlyMax(4:0)      
  
  go     				<= '1'; 
  wait for period;  
  go     				<= '0';   
  wait for 20*period;  



  testNo 				<= 2;      
  reg4x32_CSRA(0)       <= X"00001101"; -- DSPProc command (15:8) = 0b00010 001, (0) = 1. Play game 
  go     				<= '1'; 
  wait for period;  
  go     				<= '0';   
  wait for 20*period;  
  reg4x32_CSRB       <= ( others => (others => '0') ); -- clear all CSRB array         
  reg4x32_CSRB(0)(9 downto 8) <= "10"; -- assert left control bit        
  wait for 20*period;  
  reg4x32_CSRB(0)(9 downto 8) <= "01"; -- assert right control bit        
  wait for 200*period;  
  reg4x32_CSRB(0)(9 downto 8) <= "10"; -- assert left control bit        
  wait for 200*period;  
  

  wait for 2000*period; 
 
  
  --*****************************
  --This test currently covers bounce off wall, bounce bottom left corner, decrement life, reset ball and paddle, get rid of final wall piece and change game to finish mode
  --**************************
													 
  ---------------------------------------------------------------------------------------
  ----------------------This is my reset arena code--------------------------------------
  testNo <= 72;
  reg4x32_CSRA                 <= ( others => (others => '0') ); -- clear all CSRA array         
  
  reg4x32_CSRA(3)              <= X"00010000";     -- wallVec, only 1 bit left to be removed 
  
  reg4x32_CSRA(2)(31 downto 24)<= "000" & "01010"; -- "000" & ballXAdd(4:0)      
  reg4x32_CSRA(2)(23 downto 16)<= "000" & "00100"; -- "000" & ballYAdd(4:0) 
  
  reg4x32_CSRA(2)(15 downto 8) <= X"00";
  reg4x32_CSRA(2)(7  downto 0)  <= "000" & "00000"; -- "000" & score(4:0)		
  reg4x32_CSRA(2)(15 downto 8) <= "000" & "00011"; -- "000" & lives(4:0)		--lives
  
  reg4x32_CSRA(1)              <= X"00000400";     -- ball at XAdd 10
  
  reg4x32_CSRA(0)(15 downto 8) <= "00010" & "000"; -- Initialise game. At top DPSProc level, (0) would also be asserted 
  

  reg4x32_CSRB                 <= ( others => (others => '0') ); -- clear all CSRA array         

  reg4x32_CSRB(3)              <= X"0003e000";     -- paddle init

  reg4x32_CSRB(2)(31 downto 24)<= "00000" & "110"; -- ball moving NW   
  reg4x32_CSRB(2)(19 downto  0)<= X"00002";        -- dlyCount(19:0) 

  reg4x32_CSRB(1)(31 downto 24)<= "000" & "00010"; -- "000" & paddleNumDlyMax(4:0)      
  reg4x32_CSRB(1)(23 downto 16)<= "000" & "00100"; -- "000" & ballNumDlyMax(4:0)      
  
  go     				<= '1'; 
  wait for period;  
  go     				<= '0';   
  wait for 2000*period; 
  
  reg4x32_CSRA(0)       <= X"00001101"; -- DSPProc command (15:8) = 0b00010 001, (0) = 1. Play game 
  go     				<= '1'; 
  wait for period;  
  go     				<= '0';   
  wait for 20*period;
  reg4x32_CSRB       <= ( others => (others => '0') ); -- clear all CSRB array             
  wait for 200*period; 
  reg4x32_CSRB(0)(9 downto 8) <= "10";
  wait for 2000*period;						 
  ---------------------------------------------------------------------------------------
  ----------------------This is my reset arena code end----------------------------------  
				


    --*****************************
  --This test currently covers bounce top right corner, bounce off right corner of paddle
  --**************************
													 
  ---------------------------------------------------------------------------------------
  ----------------------This is my arena code--------------------------------------
  testNo <= 7122;
  reg4x32_CSRA                 <= ( others => (others => '0') ); -- clear all CSRA array         
  
  reg4x32_CSRA(3)              <= X"ffffffff";     -- wallVec, fully populated
  
  reg4x32_CSRA(2)(31 downto 24)<= "000" & "01010"; -- "000" & XAdd 10      
  reg4x32_CSRA(2)(23 downto 16)<= "000" & "00100"; -- "000" & ballYAdd(4:0) 
  
  reg4x32_CSRA(2)(7  downto 0) <= "000" & "00000"; -- "000" & score(4:0)		
  reg4x32_CSRA(2)(15 downto 8) <= "000" & "00011"; -- "000" & lives(4:0)		--lives
  
  reg4x32_CSRA(1)              <= X"00000800";     -- ballVec
  
  reg4x32_CSRA(0)(15 downto 8) <= "00010" & "000"; -- Initialise game. At top DPSProc level, (0) would also be asserted 
  

  reg4x32_CSRB                 <= ( others => (others => '0') ); -- clear all CSRA array         

  reg4x32_CSRB(3)              <= X"0003e000";     -- paddle init

  reg4x32_CSRB(2)(31 downto 24)<= "00000" & "101"; -- ball moving NE
  reg4x32_CSRB(2)(19 downto  0)<= X"00002";        -- dlyCount(19:0) 

  reg4x32_CSRB(1)(31 downto 24)<= "000" & "00010"; -- "000" & paddleNumDlyMax(4:0)      
  reg4x32_CSRB(1)(23 downto 16)<= "000" & "00100"; -- "000" & ballNumDlyMax(4:0)      
  
  go     				<= '1'; 
  wait for period;  
  go     				<= '0';   
  wait for 2000*period; 
  
  reg4x32_CSRA(0)       <= X"00001101"; -- DSPProc command (15:8) = 0b00010 001, (0) = 1. Play game 
  go     				<= '1'; 
  wait for period;  
  go     				<= '0';   
  wait for 20*period;
  reg4x32_CSRB       <= ( others => (others => '0') ); -- clear all CSRB array             
  wait for 200*period; 
  reg4x32_CSRB(0)(9 downto 8) <= "01";		--move right
  wait for 30*period;
  reg4x32_CSRB(0)(9 downto 8) <= "00";		--stop moving paddle
  wait for 1000*period;
  reg4x32_CSRB(0)(9 downto 8) <= "10";
  wait for 10*period;
  reg4x32_CSRB(0)(9 downto 8) <= "00";
  wait for 2000*period;						 
  ---------------------------------------------------------------------------------------
  ----------------------This is my arena code end----------------------------------  
												 
													 
													 
													 
  --Test top corner case                             >>>
													 -->>> Show resulting direction is aim, i.e. reflection back along path taken
  
  
  --show victory screen with wall having only one bit left and when deleted update to say you win

  
    --Test normal side to side bounce off of wall -> maybe just in one of 2 directions as same logic just reversed
  --Test bounce off edge of arena -> could be bundled in with another test aswell, maybe the one we already have as this does contain it already
  

  
  
  --Show life hitting zero and change to arena when dead

  --Score increment will be shown in another test at some stage don't think any need for dedicated test
  
  
  --would making a reset ball and reset paddle state be worthwhile? 	
  
 
  
  endOfSim 				<= true;  -- assert flag. Stops clk signal generation in process clkStim
  report "simulation done";   
  wait;                           -- include to prevent the stim process from repeating execution, since it does not include a sensitivity list
  
end process;

end Behavioral;