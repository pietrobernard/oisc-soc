library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity subbus_dev is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device manager setup
        dev_id: integer := 1;
        local_mem_begin: integer := 0;      --  start of memory space
        local_mem_nvrt: integer := 0;       --  number of virtual registers
        sram_mem_begin: integer := 0;       --  start of sram range (lies outside of the local memory range defined above)
        sram_mem_end: integer := 0;         --  end of sram range
        regcfg: string := "generic.mem"     --  logical registers configuration file
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  system bus interface signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  addendum for the sub-dev
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;          --  this line will go high if the system bus has been granted
        --  interface signals with the subdev wrapper
        dev_in_cmd: in std_logic;
        dev_in_addr: in std_logic_vector(addr_width-1 downto 0);
        dev_in_data: in std_logic_vector(data_width-1 downto 0);
        dev_in_keep: in std_logic;
        dev_in_latch: in std_logic;
        dev_out_cmd: out std_logic;
        dev_out_addr: out std_logic_vector(addr_width-1 downto 0);
        dev_out_data: out std_logic_vector(data_width-1 downto 0);
        dev_out_drdy: out std_logic;
        dev_out_done: out std_logic;
        dev_err: out std_logic;
        dev_chg: out std_logic;
        
        --  debug
        dbg_stage: out natural;
        dbg_trx_stage: out natural;
        dbg_reg_drdy: out std_logic;
        dbg_reg_done: out std_logic
    );
end subbus_dev;

architecture Behavioral of subbus_dev is
    --  constants
    constant dev_mem_begin: natural := local_mem_begin;
    constant dev_mem_end: natural := local_mem_begin + 63 + local_mem_nvrt;
    constant dev_reg_begin: natural := local_mem_begin;
    constant dev_reg_end: natural := (local_mem_begin+63);
    
    --  signals to drive and read from the bus interface
    signal r_dev_in_cmd: std_logic := '0';
    signal r_dev_in_addr: std_logic_vector(22 downto 0) := (others=>'0');
    signal r_dev_in_data: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_dev_in_keep: std_logic := '0';
    signal r_dev_in_latch: std_logic := '0';
    signal s_dev_out_cmd: std_logic;
    signal s_dev_out_addr: std_logic_vector(22 downto 0);
    signal s_dev_out_data: std_logic_vector(7 downto 0);
    signal s_dev_out_drdy: std_logic;
    signal s_dev_out_done: std_logic;
    signal s_dev_err: std_logic;
    signal s_dev_chg: std_logic;
    --  additional signals
    signal r_bus_req_sys: std_logic := '0';
    
    --  sampling the interface's output
    signal ss_dev_out_cmd: std_logic := '0';
    signal ss_dev_out_addr: std_logic_vector(22 downto 0) := (others=>'0');
    signal ss_dev_out_data: std_logic_vector(7 downto 0) := (others=>'0');
    signal ss_dev_out_drdy: std_logic := '0';
    signal ss_dev_out_done: std_logic := '0';
    signal ss_dev_err: std_logic := '0';
    signal ss_dev_chg: std_logic := '0';
    signal ss_bus_rdy_sys: std_logic := '0';
    
    --  signals to drive and sample the output interface
    signal s_int_dev_in_cmd: std_logic;
    signal s_int_dev_in_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_int_dev_in_data: std_logic_vector(data_width-1 downto 0);
    signal s_int_dev_in_keep: std_logic;
    signal s_int_dev_in_latch: std_logic;
    
    --  signals to drive the outputs
    signal r_dev_out_cmd: std_logic := '0';
    signal r_dev_out_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_dev_out_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_dev_out_drdy: std_logic := '0';
    signal r_dev_out_done: std_logic := '0';
    signal r_dev_out_chg: std_logic := '0';
    signal r_dev_out_err: std_logic := '0';
    
    --  bus busy sampling
    signal s_bus_busy: std_logic;
    
    --  state machine
    type t_SM is (
                    s_INIT, s_IDLE, s_toBUS_0, s_toBUS_1, s_toBUS_2, s_toBUS_3, s_toBUS_4, s_toBUS_5,
                    s_log_0, s_log_1, s_log_2, s_vrt_0, s_vrt_1, s_vrt_2, s_vrt_3, s_vrt_4, s_vrt_5
                 );
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    --  debug
    signal r_dbg_stage: natural := 0;
        
begin
    --  interface to the sub-system bus
    DEVINT: entity work.dev(Behavioral)
                generic map (
                    dev_id => dev_id,
                    dev_mem_begin => dev_mem_begin,
                    dev_mem_end => dev_mem_end,
                    dev_phy_begin => sram_mem_begin,
                    dev_phy_end => sram_mem_end,
                    regcfg => regcfg                    
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  external interface signals
                    dev_in_cmd => r_dev_in_cmd,
                    dev_in_addr => r_dev_in_addr,
                    dev_in_data => r_dev_in_data,
                    dev_in_keep => r_dev_in_keep,
                    dev_in_latch => r_dev_in_latch,
                    dev_out_cmd => s_dev_out_cmd,
                    dev_out_addr => s_dev_out_addr,
                    dev_out_data => s_dev_out_data,
                    dev_out_drdy => s_dev_out_drdy,
                    dev_out_done => s_dev_out_done,
                    dev_err => s_dev_err,
                    dev_chg => s_dev_chg,
                    --  debug
                    dbg_stage => dbg_trx_stage,
                    dbg_reg_drdy => dbg_reg_drdy,
                    dbg_reg_done => dbg_reg_done
                );
        
    --  main sampler and process
    SAMP:   process(sysClk)
            begin
                if (falling_edge(sysClk)) then
                    case (r_stage) is
                        when s_INIT =>
                            --  bus booking sampling
                            ss_bus_rdy_sys <= '0';
                            --  transceiver output sampling
                            ss_dev_out_cmd <= '0';
                            ss_dev_out_addr <= (others=>'0');
                            ss_dev_out_data <= (others=>'0');
                            ss_dev_out_drdy <= '0';
                            ss_dev_out_done <= '0';
                            ss_dev_err <= '0';
                            ss_dev_chg <= '0';
                            --  interface sampling
                            s_int_dev_in_cmd <= '0';
                            s_int_dev_in_addr <= (others=>'0');
                            s_int_dev_in_data <= (others=>'0');
                            s_int_dev_in_keep <= '0';
                            s_int_dev_in_latch <= '0';
                            --  busy
                            s_bus_busy <= '0';
                        
                        when s_IDLE =>
                            --  sampling bus output
                            ss_dev_out_cmd <= s_dev_out_cmd;
                            ss_dev_out_addr <= s_dev_out_addr;
                            ss_dev_out_data <= s_dev_out_data;
                            ss_dev_out_drdy <= s_dev_out_drdy;
                            ss_dev_out_done <= s_dev_out_done;
                            ss_dev_chg <= s_dev_chg;
                            --  sampling control interface
                            s_int_dev_in_cmd <= dev_in_cmd;
                            s_int_dev_in_addr <= dev_in_addr;
                            s_int_dev_in_data <= dev_in_data;
                            s_int_dev_in_keep <= dev_in_keep;
                            s_int_dev_in_latch <= dev_in_latch;
                    
                        when s_toBUS_0 =>
                            ss_dev_out_drdy <= s_dev_out_drdy;
                            ss_bus_rdy_sys <= bus_rdy_sys;
                        
                        when s_toBUS_1 =>
                            ss_dev_out_drdy <= s_dev_out_drdy;
                            ss_bus_rdy_sys <= bus_rdy_sys;
                            ss_dev_out_cmd <= s_dev_out_cmd;
                            ss_dev_out_addr <= s_dev_out_addr;
                            ss_dev_out_data <= s_dev_out_data;
                            ss_dev_out_done <= s_dev_out_done;
                        
                        when s_toBUS_2 =>
                            s_int_dev_in_latch <= dev_in_latch;
                        
                        when s_toBUS_3 =>
                            ss_dev_out_drdy <= s_dev_out_drdy;
                        
                        when s_toBUS_4 =>
                            s_int_dev_in_latch <= dev_in_latch;
                            s_int_dev_in_cmd <= dev_in_cmd;
                            s_int_dev_in_addr <= dev_in_addr;
                            s_int_dev_in_data <= dev_in_data;
                            s_int_dev_in_keep <= dev_in_keep;
                        
                        when s_log_0 =>
                            ss_dev_out_cmd <= s_dev_out_cmd;
                            ss_dev_out_addr <= s_dev_out_addr;
                            ss_dev_out_data <= s_dev_out_data;
                            ss_dev_out_drdy <= s_dev_out_drdy;
                            ss_dev_out_done <= s_dev_out_done;
                            ss_dev_chg <= s_dev_chg;
                        
                        when s_log_1 =>
                                s_int_dev_in_latch <= dev_in_latch;
                            
                        when s_log_2 =>
                            s_int_dev_in_latch <= dev_in_latch;
                            ss_dev_chg <= s_dev_chg;
                        
                        when s_vrt_0 =>
                            ss_dev_out_cmd <= s_dev_out_cmd;
                            ss_dev_out_addr <= s_dev_out_addr;
                            ss_dev_out_data <= s_dev_out_data;
                            ss_dev_out_drdy <= s_dev_out_drdy;
                            ss_dev_out_done <= s_dev_out_done;
                            ss_dev_chg <= s_dev_chg;
                        
                        when s_vrt_1 =>
                            s_int_dev_in_latch <= dev_in_latch;
                            s_int_dev_in_cmd <= dev_in_cmd;
                            s_int_dev_in_addr <= dev_in_addr;
                            s_int_dev_in_data <= dev_in_data;
                            s_int_dev_in_keep <= dev_in_keep;
                            
                        when s_vrt_2 =>
                            ss_dev_out_drdy <= s_dev_out_drdy;
                        
                        when s_vrt_3 =>
                            s_int_dev_in_latch <= dev_in_latch;
                        

                        when others => null;
                    end case;
                end if;
            end process SAMP;
    
    MAIN:   process(sysClk)
                variable cond: std_logic_vector(2 downto 0) := "000";
                variable addr: natural := 0;
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>
                                --  debug
                                r_dbg_stage <= 0;
                                --  initializing
                                r_dev_in_cmd <= '0';
                                r_dev_in_addr <= (others=>'0');
                                r_dev_in_data <= (others=>'0');
                                r_dev_in_keep <= '0';
                                r_dev_in_latch <= '0';
                                r_bus_req_sys <= '0';
                                r_dev_out_cmd <= '0';
                                r_dev_out_addr <= (others=>'0');
                                r_dev_out_data <= (others=>'0');
                                r_dev_out_drdy <= '0';
                                r_dev_out_done <= '0';
                                r_dev_out_chg <= '0';
                                r_dev_out_err <= '0';
                                --  going
                                r_stage <= s_IDLE;
                            
                            when s_IDLE =>
                                --  debug
                                r_dbg_stage <= 1;
                                --  now we have to be careful and listen for several events:
                                --  a dev_chg signal that tells us that a write/read command has occurred on a base/logical register
                                --  a dev_out_drdy signal that tells us that there's data being requested / sent (virtual register)
                                --  an event on the input interface that tells us that this device should be driving the bus.
                                cond := (ss_dev_chg & ss_dev_out_drdy & s_int_dev_in_latch);
                                case (cond) is
                                    --  this means that a base/logical register operation was completed (a write or a read)
                                    when "100" =>
                                        r_stage <= s_log_0;
                                    when "101" =>
                                        r_stage <= s_log_0;
                                    
                                    --  this means that a virtual register operation is requested
                                    when "010" =>
                                        r_stage <= s_vrt_0;
                                    when "011" =>
                                        r_stage <= s_vrt_0;
                                    
                                    when "001" =>
                                        --  this means that this device is requesting a system bus operation
                                        r_dev_in_cmd <= s_int_dev_in_cmd;
                                        r_dev_in_addr <= s_int_dev_in_addr;
                                        r_dev_in_data <= s_int_dev_in_data;
                                        r_dev_in_keep <= s_int_dev_in_keep;
                                        --  we must now book the bus (but only if the address lies outside of this device space)
                                        addr := to_integer(unsigned(s_int_dev_in_addr));
                                        if ((addr >= dev_reg_begin) and (addr <= dev_reg_end)) then
                                            --  internal address, no need to book the bus
                                            r_dev_in_latch <= '1';
                                            r_stage <= s_toBUS_1;
                                        else
                                            --  external address so we have to book the bus in advance
                                            r_bus_req_sys <= '1';
                                            r_stage <= s_toBUS_0;
                                        end if;
                                    
                                    when others =>
                                        r_stage <= s_IDLE;
                                end case;

                            when s_toBUS_0 =>
                                --  debug
                                --r_dbg_stage <= 2;
                                --  we must sample this but also ss_dev_out_drdy
                                cond := ('0' & ss_dev_out_drdy & ss_bus_rdy_sys);
                                case (cond) is
                                    when "010" =>
                                        --  failure to book the bus, we need to act as slaves -> virtual op
                                        r_dbg_stage <= 2;
                                        r_stage <= s_IDLE;
                                    
                                    when "001" =>
                                        --  bus booking ok, so disengaging the booking and latching up
                                        r_dbg_stage <= 2;
                                        r_bus_req_sys <= '0';
                                        r_dev_in_latch <= '1';
                                        r_stage <= s_toBUS_1;
                                    
                                    when others =>
                                        --  waiting
                                        r_dbg_stage <= to_integer(unsigned(cond));
                                        r_stage <= s_toBUS_0;
                                end case;
                        
                            when s_toBUS_1 =>
                                --  debug
                                r_dbg_stage <= 3;
                                --  now, the data we sent has been sent to the bridge.
                                --  the bridge is our SLAVE, while it is the MASTER of the
                                --  system bus. We need to check also for lowering of rdy_sys
                                cond := ('0' & ss_dev_out_drdy & ss_bus_rdy_sys);
                                --r_dbg_stage <= to_integer(unsigned(cond));
                                case (cond) is
                                    when "010" =>
                                        --  we are receiving a response from the bridge and
                                        --  publishing it to the outside
                                        r_dev_out_cmd <= ss_dev_out_cmd;
                                        r_dev_out_addr <= ss_dev_out_addr;
                                        r_dev_out_data <= ss_dev_out_data;
                                        r_dev_out_drdy <= ss_dev_out_drdy;
                                        r_dev_out_done <= ss_dev_out_done;
                                        --  now we have to wait for an ack
                                        r_stage <= s_toBUS_2;
                                                                    
                                    when others =>
                                        --  must wait
                                        r_stage <= s_toBUS_1;
                                end case;                                                        
                                
                            when s_toBUS_2 =>
                                --  debug
                                r_dbg_stage <= 4;
                                --  we need now to wait for the interface to acknowledge the data
                                if (s_int_dev_in_latch='0') then
                                    --  the interface has acknowledged the data                                    
                                    r_dev_out_drdy <= '0';
                                    r_dev_out_done <= '0';
                                    r_stage <= s_toBUS_3;
                                else
                                    --  waiting
                                    r_stage <= s_toBUS_2;
                                end if;
                            
                            when s_toBUS_3 =>
                                --  debug
                                r_dbg_stage <= 5;
                                --  now we need to see what we have to do
                                if (ss_dev_out_drdy='0') then
                                    --  checking the slave status
                                    if (ss_dev_out_done='0') then
                                        --  the slave indeed has more, so
                                        r_dev_in_latch <= '1';
                                        r_stage <= s_toBUS_1;
                                    else
                                        --  the slave has no more, but we might
                                        if (s_int_dev_in_keep='0') then
                                            --  no more from us
                                            r_stage <= s_IDLE;
                                        else
                                            --  we have
                                            r_stage <= s_toBUS_4;
                                        end if;                                        
                                    end if;
                                else
                                    --  waiting
                                    r_dev_in_latch <= '0';
                                    r_stage <= s_toBUS_3;
                                end if;

                            when s_toBUS_4 =>
                                --  debug
                                r_dbg_stage <= 6;
                                --  waiting for a new transaction
                                if (s_int_dev_in_latch='1') then
                                    r_dev_in_cmd <= s_int_dev_in_cmd;
                                    r_dev_in_addr <= s_int_dev_in_addr;
                                    r_dev_in_data <= s_int_dev_in_data;
                                    r_dev_in_keep <= s_int_dev_in_keep;
                                    --  launching
                                    r_dev_in_latch <= '1';
                                    r_stage <= s_toBUS_1;
                                else
                                    r_stage <= s_toBUS_4;
                                end if;
                            
                            ----------------------------------------------------------
                            --
                            --  BASE/LOGICAL register change event
                            --
                            ----------------------------------------------------------
                            when s_log_0 =>
                                --  debug
                                r_dbg_stage <= 8;
                                --  checking what happened
                                r_dev_out_cmd <= ss_dev_out_cmd;
                                r_dev_out_addr <= ss_dev_out_addr;
                                r_dev_out_data <= ss_dev_out_data;
                                r_dev_out_drdy <= ss_dev_out_drdy;
                                r_dev_out_done <= ss_dev_out_done;
                                r_dev_out_err <= ss_dev_err;
                                r_dev_out_chg <= ss_dev_chg;
                                --  waiting now for the ack
                                r_stage <= s_log_1;
                            
                            when s_log_1 =>
                                --  debug
                                r_dbg_stage <= 9;
                                if (s_int_dev_in_latch='1') then
                                    --  acknowledging the change
                                    r_dev_out_chg <= '0';
                                    r_dev_in_latch <= '1';
                                    r_stage <= s_log_2;
                                else
                                    --  waiting for the change
                                    r_stage <= s_log_1;
                                end if;
                            
                            when s_log_2 =>
                                --  debug
                                r_dbg_stage <= 10;
                                if ((s_int_dev_in_latch='0') and (ss_dev_chg='0')) then
                                    --  we can go forward
                                    r_dev_in_latch <= '0';
                                    r_stage <= s_IDLE;
                                else
                                    --  waiting
                                    r_stage <= s_log_2;
                                end if;
                            
                            ----------------------------------------------------------
                            --
                            --  VIRTUAL register event
                            --
                            ----------------------------------------------------------
                            when s_vrt_0 =>
                                --  debug
                                r_dbg_stage <= 11;
                                --  sending data over
                                r_dev_out_cmd <= ss_dev_out_cmd;
                                r_dev_out_addr <= ss_dev_out_addr;
                                r_dev_out_data <= ss_dev_out_data;
                                r_dev_out_drdy <= ss_dev_out_drdy;
                                r_dev_out_done <= ss_dev_out_done;
                                r_dev_out_err <= ss_dev_err;
                                r_dev_out_chg <= ss_dev_chg;
                                --  waiting for ack
                                r_stage <= s_vrt_1;
                            
                            when s_vrt_1 =>
                                --  debug
                                r_dbg_stage <= 12;
                                --  now I need to wait for the interface to latch in a response
                                if (s_int_dev_in_latch='1') then
                                    --  here's the response that I have to place on the bus, so:
                                    r_dev_in_cmd <= s_int_dev_in_cmd;
                                    r_dev_in_addr <= s_int_dev_in_addr;
                                    r_dev_in_data <= s_int_dev_in_data;
                                    r_dev_in_keep <= s_int_dev_in_keep;
                                    --  latching the response on the bus while keeping the interface locked
                                    r_dev_in_latch <= '1';
                                    r_stage <= s_vrt_2;
                                else
                                    --  waiting for a response
                                    r_stage <= s_vrt_1;
                                end if;
                            
                            when s_vrt_2 =>
                                --  debug
                                r_dbg_stage <= 13;
                                --  now I latched the response back to the bus and I must check for the interface too
                                if (ss_dev_out_drdy='0') then
                                    --  this means that the remote-end has acknowledged the data, must now see if I have to send more
                                    r_dev_in_latch <= '0';
                                    --  signalling that it must release the s_int_dev_in_latch
                                    r_dev_out_drdy <= '0';
                                    r_dev_out_done <= '0';
                                    --  going
                                    r_stage <= s_vrt_3;
                                else
                                    --  waiting
                                    r_stage <= s_vrt_2;
                                end if;
                            
                            when s_vrt_3 =>
                                --  debug
                                r_dbg_stage <= 14;
                                --  check
                                if (s_int_dev_in_latch='0') then
                                    --  the interface is unlocked, must see what we have to do
                                    if (s_int_dev_in_keep='1') then
                                        --  we have more bytes to send over to the master
                                        r_dev_out_drdy <= '1';
                                        r_stage <= s_vrt_1;
                                    else
                                        --  no more to send to the master, but the master might or may not have more for us
                                        r_stage <= s_IDLE;
                                    end if;
                                else
                                    --  waiting for interface to unlock
                                    r_stage <= s_vrt_3;
                                end if;
                                    
                            
                            when others =>
                                r_stage <= s_IDLE;
                        end case;
                    end if;
                end if;
            end process MAIN;
    
    --  assignment
    bus_req_sys <= r_bus_req_sys;
    dev_out_cmd <= r_dev_out_cmd;
    dev_out_addr <= r_dev_out_addr;
    dev_out_data <= r_dev_out_data;
    dev_out_drdy <= r_dev_out_drdy;
    dev_out_done <= r_dev_out_done;
    dev_err <= r_dev_out_err;
    dev_chg <= r_dev_out_chg;
    --  debug
    dbg_stage <= r_dbg_stage;
    
end Behavioral;