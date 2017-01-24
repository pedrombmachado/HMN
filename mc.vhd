
Library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;
use work.utility_package.all;
use work.settings_package.all;

entity mc is

port (
	clk				: IN std_logic; -- 50 MHz clock
	resetBut			: IN STD_LOGIC;
	spiInReady		: IN std_logic; -- SPI
	spiIn				: IN std_logic_vector(7 downto 0);
	spiTX				: IN std_logic;
	spiOutReady		: OUT std_logic; -- SPI
	spiOut			: OUT std_logic_vector (7 downto 0); -- SPI
	resetTrigger	: OUT std_logic;
	txReq				: OUT std_logic; -- SPI
	debug				: OUT std_logic_vector (2 downto 0)
	);
end mc;

-- architecture body --

ARCHITECTURE mc_arch OF mc IS
	
	component single_clock_ram
		port 
			(
				clk	: in std_logic;
				raddr	: in std_logic_vector(15 downto 0);
				waddr	: in std_logic_vector(15 downto 0);
				data	: in std_logic_vector(39 downto 0);
				we	: in std_logic;
				q	: out std_logic_vector(7 downto 0)
			);
	end component single_clock_ram;
	component MM
		generic 
			(
				ID				: natural;	-- model ID
				MAX_NEURONS : natural;  -- maximum number of neurons
				SPKWIDTH		: natural;	-- spikes BUS width
				CONTROLBUS 	: natural;	-- Control BUS width
				ITEMID_SIZE	: natural;	-- Control BU
				READBACKBUS	: natural	-- Readback BUS width
			);		
		port (
				clk: 			IN std_logic; -- 100 MHz clock
				reset: 		IN std_logic; -- sync clock
				commandBUS:	IN std_logic_vector(8 downto 0);		
				neuronBUS: 	IN std_logic_vector(15 downto 0); 
				itemIdBUS:	IN std_logic_vector(15 downto 0); 
				valuesBUS: 	IN std_logic_vector (31 downto 0); -- N/M model
				neuronOut: 	OUT std_logic -- N/M model
				neuronValue:OUT std_logic_vector (31 downto 0); -- N/M model
			);
	end component MM;
	component resetTrig
		PORT(	
				clk	: IN STD_LOGIC;
				resetTri				: IN STD_LOGIC;
				resetBut				: IN STD_LOGIC;
				reset					: OUT STD_LOGIC
				);		
	end component resetTrig;
	signal instruction 		: std_logic_vector(7 downto 0) := (others => '0');
	signal byteCount			: natural range 0 to 3;
	
	signal writeOp				: std_logic_vector(ITEMID_SIZE+31 downto 0) := (others => '0');
	signal readOp				: std_logic_vector(ITEMID_SIZE-1 downto 0) := (others => '0');
	signal spikeTrain			: std_logic_vector(31 downto 0) := (others => '0');
	signal spkCounter			: natural := 0;
	signal netTopology		: std_logic_vector(MAX_NEURONS-1 downto 0) := (others => '0');

	signal restoreState_aux	: std_logic :='0';
	signal conf_flags			: std_logic_vector(5 downto 0) := (others => '0');
	signal runStep_aux		: std_logic :='0';
	signal payload				: natural;
	signal timestamp			: std_logic_vector(63 downto 0) := (others => '0');
--	signal readBuffer			: std_logic_vector(39 downto 0) := (others => '0');
--	signal read_flag			: std_logic :='0';
	
	signal queueProc			: integer :=0;
	signal busy_flag			: std_logic := '0';
	signal payload_flag		: std_logic := '0';
	
	signal spiOut_aux			: std_logic_vector (7 downto 0) := (others => '0');
	signal spiOutReady_aux	: std_logic := '0';
	signal count	 			: natural;
	signal txreq_aux			: std_logic := '0';
	signal counter				: natural :=0;
	signal readdata_aux			: std_logic :='0';
	signal itemid				: std_logic_vector(15 downto 0);
	signal reset				: std_logic:= '0'; -- sync reset
	
	-- BRAM
	signal data:	std_logic_vector(39 downto 0) := (others => '0');
	signal waddr:	std_logic_vector(15 downto 0) := (others => '0');
	signal raddr:	std_logic_vector(15 downto 0) := (others => '0');
	signal we:		std_logic := '0';
	signal q:		std_logic_vector(7 downto 0);
	
	-- neuron model interface
	signal commandBUS: 	std_logic_vector(7 downto 0); 
	signal neuronBUS: 	std_logic_vector(15 downto 0); 
	signal itemIdBUS:		std_logic_vector(15 downto 0); 
	signal valuesBUS: 	std_logic_vector (31 downto 0); -- N/M model
	signal neuronOut: 	std_logic_vector(NUM_MODELS-1 downto 0); -- N/M model
	signal neuronValue:	std_logic_vector (31 downto 0);

	
	-- reset trigger
	signal resetTri:		std_logic;
	
	
BEGIN
	ram: single_clock_ram
		port map (
			clk=>clk,
			raddr=>raddr,
			waddr=>waddr,
			data=>data,
			we=>we,
			q=>q
			);
			
	neuron: for I in 0 to NUM_MODELS-1 generate
		neuron_num: MM
		generic map (
			ID => ID(I),
			MAX_NEURONS => MAX_NEURONS,
			SPKWIDTH => SPKWIDTH,
			CONTROLBUS=> CONTROLBUS,
			ITEMID_SIZE=> ITEMID_SIZE,
			READBACKBUS=> READBACKBUS
			)
		port map (
			clk   => clk,
			reset => reset,
			commandBUS=>commandBUS,
			neuronBUS=>neuronBUS,
			itemIdBUS=>itemIdBUS,
			valuesBUS=>valuesBUS,
			neuronOut=>neuronOut(I),
			neuronValue=>neuronValue(I)
		);
	end generate;

	reset_circuit:resetTrig
		port map(
			clk=>clk,
			resetTri=>resetTri,
			resetBut=>resetBut,
			reset=>reset
		);
	
--wrapper: process(clk, reset)--, read_flag, readBuffer)
--	begin
--	if clk'event and clk='1' then 
--		if reset='1' then
--			waddr<= (others => '0');
--			data<= (others => '0');
--			we <='0';
--			busy_flag<='<=(others =>'0');0';
--		else
--			if busy='1' and busy_flag='0' then
--				busy_flag<='1';
--			elsif busy='0' and busy_flag='1' then
--				data(31 downto 0)<=readBckBus(31 downto 0);
--				data(39 downto 32)<="100"&std_logic_vector(to_unsigned(ID,4))&'0';
--				we<='1';
--				busy_flag<='0';
--			else
--				-- nothing happens
--			end if;
--			
--			if we='1' then
--				if to_integer(unsigned(waddr))+5>509 then
--					waddr<=(others=>'0');
--				else
--					waddr<=waddr+5;
--				end if;
--				we<='0';
--			else
--				-- nothing happens
--			end if;
--		end if;
--		-- write to output ports
--		we<=we;
--		waddr<=waddr;
--		data<=data;
--	else
--		--nothing happens
--	end if;
--end process;
--
--dispatcher: process(clk, reset, waddr)
--	begin
--	if clk'event and clk='1' then 
--		if reset='1' then
--			raddr<= (others => '0');
--			queueProc<=0;
--			counter<=0;
--			spiOut_aux<=(others =>'0');
--			spiOutReady_aux<='0';
--			txreq_aux<='0';
--		else
--			if raddr<waddr then
--				queueProc<= to_integer(unsigned(waddr-raddr));
--			elsif raddr>waddr then
--				queueProc<= 510-to_integer(unsigned(raddr-waddr));
--			else
--				queueProc<=0;
--			end if;
--			
--			if counter=0 and raddr/=waddr and spiTX='0' then
--				txreq_aux<='1';
--			else
--				--nothing happens
--			end if;
--			
--			if counter=0 and raddr/=waddr and spiTX='1' then
--				spiOut_aux<=q;
--				spiOutReady_aux<='1';
--				counter<=counter+1;
--				txreq_aux<='1';
--			elsif counter=1 then
--				if raddr<509 and raddr/=waddr then -- 509-1
--					raddr<=raddr+1;
--				else
--					raddr<=(others =>'0');
--				end if;
--				spiOutReady_aux<='0';
--				txreq_aux<='0';
--				counter<=counter+1;
--			elsif counter>1 and counter<TXDELAY*20 then
--				counter<=counter+1;
--			elsif counter=TXDELAY*20 then
--				counter<=0;
--			else
--				-- nothing happens
--			end if;
--		end if;
--		-- write to output ports
--		txreq<=txreq_aux;
--		raddr<=raddr;
--		spiOut<=spiOut_aux;
--		spiOutReady<=spiOutReady_aux;
--	else
--		--nothing happens
--	end if;
--end process;

spiController: process(clk, reset)
	begin
	if clk'event and clk='1' then 
		if reset='1' then
			count<=0;
			commandBUS<=(others => '0'); 
			neuronBUS<=(others => '0'); 
			itemIdBUS<=(others => '0');
			valuesBUS<=(others => '0'
			resetTri<='0';
			instruction<=(others =>'0');
			readOp<=(others =>'0');
			writeOp<=(others =>'0');
			spikeTrain<=(others =>'0');
			netTopology<=(others =>'0');
			byteCount<=0;
			spkCounter<=1;-- MSB -- > LSB - 9x 32bits + 1x 16bits
		else
			
			if spiInReady='1' and count=0 then
				count<=count+1;
				if spiIn=x"FA" then -- resetFPGA
					instruction(0)<='1';
					payload<=0;
					payload_flag<='1';
					byteCount<=0;
				elsif spiIn=x"01" then -- confNetTopology
					instruction(1)<='1';
					payload<=39;
					payload_flag<='0';
					byteCount<=0;
				elsif spiIn=x"02" then -- runStep
					instruction(2)<='1';
					payload<=39;
					payload_flag<='0';
					byteCount<=0;
					spkCounter<=1; -- MSB -- > LSB - 9x 32bits + 1x 16bits
				elsif spiIn=x"03" then -- write
					instruction(3)<='1';
					payload<=5;
					payload_flag<='0';
					byteCount<=0;
				elsif spiIn=x"04" then -- read
					instruction(4)<='1';
					payload<=1;
					payload_flag<='0';
					byteCount<=0;
				else -- others 
					-- nothing happens
				end if;
			else
				-- nothing happens
			end if;
			
			if spiInReady='1' and count>0 and payload_flag='0' then
				if payload>0 then
					payload<=payload-1;
					byteCount<=byteCount+1;
				else
					payload_flag<='1';
				end if;
				if byteCount=0 then
					neuronBUS(15 downto 8)<=spiIn;
				elsif byteCount=1 then
					neuronBUS(7 downto 0)<=spiIn;
				elsif byteCount=2 then
					if instruction(3)='1' or instruction(4)='1' then -- read or write
						itemIdBUS(15 downto 8)<=spiIn;
					else
						itemIdBUS(15 downto 8)<=x"00";
					end if;
				elsif byteCount=4 then
					if instruction(3)='1' or instruction(4)='1' then -- read or write
						itemIdBUS(7 downto 0)<=spiIn;
					else -- no item id
						itemIdBUS(7 downto 0)<=x"00";
					end if;
				
					
					
					
				if instruction(1)='1' and payload<=37 then -- confNetTopology
					netTopology(payload*8+7 downto payload*8)<=spiIn;
				
				
				elsif instruction(2)='1' and payload<=37 then -- runStep
					spikeTrain(spkCounter*8+7 downto spkCounter*8)<=spiIn and netTopology(((payload*8)+7) downto (payload*8)) ; --(((payload*8)+7) downto (payload*8))
					if spkCounter= 0 then
						commandBUS(2 downto 0)<=(others =>'0');
						commandBUS(3)<='1';  -- Update spike train
						commandBUS(7 downto 4)<=(others =>'0');
						spkCounter<=3;
					else
						spkCounter<=spkCounter-1;
					end if
					
					
				
			elsif count>0 and payload_flag='1' and payload=0 then
				if instruction(0)='1' then -- resetFPGA
						neuronBUS<=(others => '0');
						resetTri<='1';
		
				elsif instruction(1)='1' then -- confNetTopology
						report "Net topology value = " & natural'image(to_integer(unsigned(netTopology))) & ", Neuron ID "& natural'image(ID) severity note;
						neuronBUS<=(others => '0');
						conf_flags(5)<='1';
						
				elsif instruction(2)='1' and queueProc<490 then -- runStep
					if conf_flags(4)='1' and conf_flags(3)='1' and conf_flags(0)='1' and conf_flags(5)='1' then
						commandBUS(0)<=x"01"; 
						timestamp<=timestamp+1;
						conf_flags(1)<='1';
					else
--						err_flag<='1';
--						err<=x"03"; -- Error a run step can only be processed after configuring the simulation
					end if;
				
						
				elsif instruction(3)='1' then -- write
					readdata_aux<='0';
					restoreState_aux<='1';
					itemid<=writeOp(47 downto 32);
					
				elsif instruction(4)='1' then -- read TO DO: need to check
						readdata_aux<='1';
						restoreState_aux<='0';
					
				else
					-- last state
				end if;
				instruction<=(others =>'0');
				count<=0;
			else
				-- TO DO
			end if;
			if resetTri='1' then
				resetTri<='0';
			else
				-- nothing happens
			end if;
			
			if commandBUS>x"00" then
				commandBUS<=x"00";
			else
				--nothing happens
			end if;

		end if;
		-- write to output ports
		restoreState<=restoreState_aux;
		resetTrigger<=resetTri;
		readData<=readdata_aux;
		runStep<=runStep_aux;
		contBus(SPKWIDTH-1 downto 0)<= spikeTrain;
		contBus(SPKWIDTH+ITEMID_SIZE-1 downto SPKWIDTH)<=itemid;
		contBus(SPKWIDTH+CONTROLBUS+ITEMID_SIZE-1 downto SPKWIDTH+ITEMID_SIZE)<=writeOp(31 downto 0);
		debug<=not(conf_flags(4))&not(conf_flags(3))&not(busy);
	else
		--nothing happens
	end if;
end process;
end mc_arch;
