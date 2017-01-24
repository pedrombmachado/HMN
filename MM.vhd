Library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;
use ieee.fixed_float_types.all;
--!ieee_proposed for fixed point
use ieee.fixed_pkg.all;
--!ieee_proposed for floating point
use ieee.float_pkg.all;

entity MM is

generic 
	(
		ID				: natural;	-- model ID
		MAX_NEURONS	: natural;	-- maximum number of neurons
		SPKWIDTH		: natural;	-- spikes BUS width
		CONTROLBUS 	: natural;	-- Control BUS width
		ITEMID_SIZE	: natural;	-- Control BU
		READBACKBUS	: natural	-- Readback BUS width
	);		

port (	clk		: IN std_logic; -- 100 MHz clock
	reset		: IN std_logic; -- sync clock
	runStep		: IN std_logic; -- N/M model
	restoreState	: IN std_logic; -- N/M model
	readData:		IN std_logic;
	contBus		: IN std_logic_vector ((CONTROLBUS+ITEMID_SIZE+SPKWIDTH)-1 downto 0);; -- N/M model
	readBckBus	: OUT std_logic_vector (READBACKBUS-1 downto 0); -- N/M model
	busy		: OUT std_logic -- N/M model
	);
end MM;

architecture MM_arch of MM is

signal 	k:				float32;
signal 	m:				natural range 1 to 20;
signal 	A:				float32;
signal 	B:				float32;
signal 	C:				float32;
signal 	D:				float32;
signal 	dt:			float32;
signal 	v1:			float32;
signal 	v2:			float32;
signal 	v3:			float32;
signal	current:		float32;
signal 	count:		natural					:=0;
signal	conf_flag:	std_logic_vector (2 downto 0) 		:="000";
signal	compute_flag:	std_logic 				:='0';
signal	busy_aux:	std_logic 				:='0';
signal	rkAux0:		float32;
signal	rxAux1:		float32;
signal	rkAux2:		float32;
signal	rxAux3:		float32;
signal	rk22_flag:	std_logic 				:='0';
signal	rk2_flag:	std_logic 				:='0';
signal	currentLast: 	float32;
signal	forces:	float32;
signal 	forces_aux:	float32;

--function spikes2current(contBus: std_logic_vector (SIS-1 downto 0); current: std_logic_VECTOR (11*32-1 downto 0)) return float32 is
--	variable current: float32 := (others =>'0');
--	variable pos :	natural range 0 to 10 :=0;
--	begin
--		for I in 0 to SIS-1 loop
--			if contBus(I)='1' and pos < 11 then
--				current:=current + to_float(current(32+pos*32-1 downto pos*32),current);
--				pos:=pos+1;
--			else
--				-- do nothing
--			end if;
--		end loop;
--		return current;
--	end spikes2current;

BEGIN
	muscle: process(clk, reset, v1, v2, rk2_flag, rk22_flag)
--	variable contBusAux:	std_logic_vector (SIS-1 downto 0);
	variable iterator : natural range 0 to 19 :=0;
	begin
	if clk'event and clk='1' then 
		if reset='1' then
			forces<=to_float(0.0,forces);
			forces_aux<=to_float(0.0,forces_aux);
			conf_flag<="000";
			count<=0;
			compute_flag<='0';
			dt<=to_float(0.0,dt);	-- 0.05
			A<=to_float(0.0,A);	-- 1.0
			B<=to_float(0.0,B);	-- 25.0
			C<=to_float(0.0,C);	-- -0.015
			D<=to_float(0.0,D);	-- 14.0
			k<=to_float(0.0,k);	-- 0.53
			m<=1;	-- 5
			current<=to_float(0.0,current);
			busy_aux<='0';
			current<=to_float(0.0,current);
			readBckBus<= (others => '0');
			iterator:=0;
		else
			if restoreState='1' then
				-- 11 current max
				dt<=to_float(contBus(39 downto 8),dt);
				if to_integer(unsigned(contBus(7 downto 0)))=1 then -- Linear Muscle Model
					-- (the three thetas)
					A<=to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A); 
					D<=to_float(contBus(RESERVEDC+95 downto RESERVEDC+64),D)/to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A); 
					C<=to_float(contBus(RESERVEDC+127 downto RESERVEDC+96),C)/to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A);
					B<=to_float(contBus(RESERVEDC+159 downto RESERVEDC+128),B)/to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A);
					forces<=to_float(contBus(RESERVEDC+191 downto RESERVEDC+160),forces);
					conf_flag<="001";
				elsif to_integer(unsigned(contBus(7 downto 0)))=2 then -- Adapted Muscle Model
					-- (A, tauc, tau1)
					A<=to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A);
					B<=to_float(contBus(RESERVEDC+95 downto RESERVEDC+64),B); -- tau1
					C<=to_float(contBus(RESERVEDC+127 downto RESERVEDC+96),C); -- tauc
					forces<=to_float(contBus(RESERVEDC+159 downto RESERVEDC+128),forces); -- float32
					conf_flag<="010";
				else -- Wiener Muscle Model
					-- 5 for wiener (the thetas and k, m)
					A<=to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A); 
					D<=to_float(contBus(RESERVEDC+95 downto RESERVEDC+64),B)/to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A); 
					C<=to_float(contBus(RESERVEDC+127 downto RESERVEDC+96),C)/to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A);
					B<=to_float(contBus(RESERVEDC+159 downto RESERVEDC+128),D)/to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A);
					forces<=to_float(contBus(RESERVEDC+191 downto RESERVEDC+160),forces)/to_float(contBus(RESERVEDC+63 downto RESERVEDC+32),A);
					k<=to_float(contBus(RESERVEDC+223 downto RESERVEDC+192),k);
					m<=to_integer(unsigned(contBus(RESERVEDC+231 downto RESERVEDC+224))); -- uint8
					conf_flag<="100";
				end if;
			else
				-- nothing happens
			end if;
			
--			if conf_flag=0 and runStep='1' then
--				readBckBus(RESERVEDR-1 downto 0)<=x"FFFE";
--			else
--				-- nothing happens
--			end if;

			if conf_flag>0 and runStep='1' and count=0 then
--				contBusAux:=contBus(SIS-1 downto 0);
--				current<=spikes2current(contBusAux, current);
				count<=count+1;
				compute_flag<='1';
				busy_aux<='1';
				count<=count+1;
				current<=to_float(contBus(RESERVEDC+31 downto RESERVEDC),current);
				
			elsif count=1 then
				compute_flag<='0';
				count<=count+1;
				forces_aux<=to_float(0.0,forces_aux);
				
			elsif count=2 and (rk22_flag='1' or rk2_flag='1') then 
				if conf_flag="100" then
					if iterator+1< m then
						forces<=forces*v1;
						forces_aux<=forces_aux*k;
						iterator:=iterator+1;
					else
						iterator:=0;
						forces<=forces*v1;
						forces_aux<=forces_aux*k;
						count<=count+1;
					end if;
				elsif conf_flag="001" then
					forces<=v1;
					count<=5;
				elsif conf_flag="010" then
					forces<=v3;
					count<=5;
				else
					-- nothing happens
				end if;
			
			elsif count=3 then
				forces_aux<=forces+forces_aux;
				count<=count+1;

			elsif count=4 then
				forces<=to_float(100.0,forces)*forces/forces_aux; -- check 100 because the value must be between 0 -255 (0 and 1)
				count<=count+1;
			
			elsif count=5 then
				busy_aux<='0';
				count<=0;
			else
			-- nothing happens
			end if;
			--readBckBus(RESERVEDR+7 downto RESERVEDR+0)<=x"01";
			--readBckBus(RESERVEDR+15 downto RESERVEDR+8)<=x"02";
			--readBckBus(RESERVEDR+23 downto RESERVEDR+16)<=x"03";
			--readBckBus(RESERVEDR+31 downto RESERVEDR+24)<=x"04";
			readBckBus(31 downto 0)<=to_slv(forces);
			busy<=busy_aux;
		end if;	
		else
			-- nothing happens
		end if;
	end process;
	
	linearWiener : process(clk, reset, conf_flag, compute_flag, A, B, C, D, dt, current)
	variable	countRK:	natural					:=0;
	variable	M1A:		float32;
	variable 	M1B:		float32;
	variable	M1C:		float32;
	variable 	M1D:		float32;
	variable	M2A:		float32;
	variable 	M2B:		float32;
	variable	K1A:		float32;
	variable 	K1B:		float32;
	variable	q1A:		float32;
	variable	q1B:		float32;
	variable	K2A:		float32;
	variable	K2B:		float32;
	variable	q2A:		float32;
	variable	q2B:		float32;
	variable	K3A:		float32;
	variable	K3B:		float32;
	variable	q3A:		float32;
	variable	q3B:		float32;
	variable	K4A:		float32;
	variable	K4B:		float32;
	begin
	if clk'event and clk='1' then 
		if reset='1' then
			v1<=to_float(0.0,v1);
			v2<=to_float(0.0,v2);
			countRK:=0;
			rk22_flag<='0';
			K1A:=to_float(0.0,K1A);
			K1B:=to_float(0.0,K1B);
			K2A:=to_float(0.0,K2A);
			K2B:=to_float(0.0,K2B);
			K3A:=to_float(0.0,K3A);
			K3B:=to_float(0.0,K3B);
			K4A:=to_float(0.0,K4A);
			K4B:=to_float(0.0,K4B);
			q1A:=to_float(0.0,q1A);
			q1B:=to_float(0.0,q1B);
			q2A:=to_float(0.0,q2A);
			q2B:=to_float(0.0,q2B);
			q3A:=to_float(0.0,q3A);
			q3B:=to_float(0.0,q3B);
			M1A:=to_float(0.0,M1A);
			M1B:=to_float(0.0,M1B);
			M1C:=to_float(0.0,M1C);
			M1D:=to_float(0.0,M1D);
			M2A:=to_float(0.0,M2A);
			M2B:=to_float(0.0,M2B);
			rkAux0<=to_float(0.0,rkAux0);
			rxAux1<=to_float(0.0,rxAux1);
			rkAux2<=to_float(0.0,rkAux2);
			rxAux3<=to_float(0.0,rxAux3);
		else
			if countRK=0 and compute_flag='1' and (conf_flag="100" or conf_flag="001") then
				M1A:= to_float(0.0,M1A);
				M1B:= -C;
				M1C:= -B;
				M1D:= -A;
				M2A:= to_float(0.0,M2A);
				M2B:= D;
				countRK:=countRK+1;
			
			elsif countRK=1 then
				K1A:=M1B*v2;
				K1B:=M1D*v2;
				countRK:=countRK+1;
			
			elsif countRK=2 then
				K1A:=K1A+M2A*current;
				K1B:=K1B+M2B*current;
				countRK:=countRK+1;
			
			elsif countRK=3 then
				K1A:=M1A*v1 + K1A;
				K1B:=M1C*v1 + K1B;
				q1A:=dt*to_float(0.5,q1A);
				q1B:=dt*to_float(0.5,q1B);
				countRK:=countRK+1;
			
			elsif countRK=4 then
				q1A:=v1+K1A*q1A;
				q1B:=v2+K1B*q1B;
				K2A:=M2A*current;
				K2B:=M2B*current;
				countRK:=countRK+1;
				
			elsif countRK=5 then
				K2A:=M1B*q1B+K2A;
				K2B:=M1D*q1B+K2B;
				countRK:=countRK+1;
			
			elsif countRK=6 then
				K2A:=M1A*q1A+K2A;
				K2B:=M1C*q1A+K2B;
				q2A:=dt*to_float(0.5,q2A);
				q2B:=dt*to_float(0.5,q2B);
				countRK:=countRK+1;
				
			elsif countRK=7 then
				q2A:=v1+K2A*q2A;
				q2B:=v2+K2B*q2B;
				K3A:=M2A*current;
				K3B:=M2B*current;
				countRK:=countRK+1;
				
			elsif countRK=8 then
				K3A:=M1B*q2B+K3A;
				K3B:=M1D*q2B+K3B;
				countRK:=countRK+1;
				
			elsif countRK=9 then
				K3A:=M1A*q2A + K3A;
				K3B:=M1C*q2A + K3B;
				q3A:=dt*to_float(0.5,q2A);
				q3B:=dt*to_float(0.5,q2B);
				countRK:=countRK+1;
				
			elsif countRK=10 then
				q3A:=v1+K3A*q3A;
				q3B:=v2+K3B*q3B;
				K4A:=M2A*current;
				K4B:=M2B*current;
				countRK:=countRK+1;
				
			elsif countRK=11 then
				K4A:=M1B*q3B+K4A;
				K4B:=M1D*q3B+K4B;
				countRK:=countRK+1;
			
			elsif countRK=12 then
				K4A:=M1A*q3A + K4A;
				K4B:=M1C*q3A + K4B;
				countRK:=countRK+1;
				
			elsif countRK=13 then
				rkAux0<=K1A + 2*K2A + 2*K3A + K4A;
				rxAux1<=K1B + 2*K2B + 2*K3B + K4B;
				rkAux2<=to_float(0.16666666666666666,rkAux2)*dt;
				rxAux3<=to_float(0.16666666666666666,rxAux3)*dt;
				countRK:=countRK+1;
				
			elsif countRK=14 then
				v1<=v1+rkAux0*rkAux2;
				v2<=v2+rxAux1*rxAux3;
				countRK:=countRK+1;
			
			elsif countRK=15 then
				rk22_flag<='1';
				countRK:=countRK+1;
				
			elsif countRK=16 then
				rk22_flag<='0';
				countRK:=0;
			else
				--nothing happens
			end if;
		end if;
	else
		-- nothing happens
	end if;
	end process;

	Adapted: process(clk, reset, compute_flag, conf_flag, A, B, C, dt, current)
	variable	countRK:	natural			:=0;
	variable	K1:		float32;
	variable 	K2:		float32;
	variable 	q:		float32;
	variable 	Cn:		float32;
	begin
	if clk'event and clk='1' then 
		if reset='1' then
			v3<=to_float(0.0,v3);
			countRK:=0;
			rk2_flag<='0';
			K1:=to_float(0.0,K1);
			K2:=to_float(0.0,K2);
			q:=to_float(0.0,q);
			Cn:=to_float(0.0,Cn);
			currentLast<=to_float(0.0,currentLast);
		else
			if countRK=0 and compute_flag='1' and conf_flag="010" then
				K1:=-Cn/C+currentLast;
				countRK:=countRK+1;
				currentLast<=current;
				
			elsif countRK=1 then
				countRK:=countRK+1;
				q:=Cn+K1*dt;
				
			elsif countRK=2 then
				K2:=-q/C+current;
				countRK:=countRK+1;
				
			elsif countRK=3 then
				Cn:=Cn+K2*to_float(0.05,Cn);
				K1:=-v3/B;
				countRK:=countRK+1;
				
			elsif countRK=4 then
				K1:=K1+A*Cn;
				countRK:=countRK+1;
				
			elsif countRK=5 then
				q:=v3+K1*dt;
				K2:=A*Cn;
				countRK:=countRK+1;
				
			elsif countRK=6 then
				K2:=-q/B+K2;
				countRK:=countRK+1;
				
			elsif countRK=7 then
				v3<=v3+K2*to_float(0.05,Cn);
				countRK:=countRK+1;
				rk2_flag<='1';
				
			elsif countRK=8 then
				rk2_flag<='0';
				countRK:=0;
			else
				--nothing happens
			end if;
		end if;
	else
		-- nothing happens
	end if;
	end process;
END MM_arch;