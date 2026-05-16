library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity subdev_GPIO_portA is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  hardware id for the UART
        --  this allows for data-packets sent from the uart device to reach this and not other sub-devs of the uart
        hw_id: integer := 0;
        --  device manager setup
        dev_id: integer := 1;
        local_mem_begin: integer := 0;      --  start of memory space
        local_mem_nvrt: integer := 0;       --  number of virtual registers
        sram_mem_begin: integer := 0;       --  start of sram range (lies outside of the local memory range defined above)
        sram_mem_end: integer := 0;         --  end of sram range
        regcfg: string := "generic.mem";    --  logical registers configuration file
        delay: natural := 10000000          --  sampling the port every 10 milliseconds
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  sub-system signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;          --  this line will go high if the system bus has been granted
        --  hardware databus lanes
        extport: inout std_logic_vector(data_width-1 downto 0);
        drdy: in std_logic;
        dack: out std_logic
    );
end subdev_GPIO_portA;

architecture Behavioral of subdev_GPIO_portA is
    --  external port control
    signal r_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal s_data_from: std_logic_vector(data_width-1 downto 0);
    signal r_ddir: std_logic := '0';
    signal r_dack: std_logic := '0';
    
    --  subdev interface
    signal r_bus_in_cmd: std_logic := '0';
    signal r_bus_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_in_keep: std_logic := '0';
    signal r_bus_in_latch: std_logic := '0';
    
    --  sampling sub-bus
    signal s_bus_out_cmd: std_logic;
    signal s_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_bus_out_drdy: std_logic;
    signal s_bus_out_done: std_logic;
    signal s_bus_err: std_logic;
    signal s_bus_chg: std_logic;
    
    --  sampling signals
    signal ss_bus_out_drdy: std_logic;
    signal ss_bus_out_done: std_logic;
    signal ss_bus_err: std_logic;
    signal ss_bus_chg: std_logic;
    signal ss_drdy: std_logic;
    
    --  flag
    signal r_flag: std_logic := '0';
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_PORT_0, s_PORT_1, s_PORT_2, s_REG_0, s_VRT_0, s_VRT_1, s_VRT_2, s_VRT_3, s_PRE_0);
    signal r_stage: t_SM := s_INIT;
    signal r_stage_p: t_SM := s_PORT_0;
begin
    --  hardware port driver
    DATA_DRV:   entity work.inout_port(Behavioral)
                generic map (
                    nbits => 8
                ) port map (
                    io => extport,
                    data_to => r_data_to,
                    data_from => s_data_from,
                    dir => r_ddir
                );

    --  drivers
    dack <= r_dack;

    --  subbus
    SBUSINT:    entity work.subbus_dev(Behavioral)
                generic map (
                    dev_id => dev_id,
                    local_mem_begin => local_mem_begin,
                    local_mem_nvrt => local_mem_nvrt,
                    regcfg => regcfg
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  addendum for the sub-dev
                    bus_req_sys => bus_req_sys,
                    bus_rdy_sys => bus_rdy_sys,
                    --  interface signals
                    dev_in_cmd => r_bus_in_cmd,
                    dev_in_addr => r_bus_in_addr,
                    dev_in_data => r_bus_in_data,
                    dev_in_keep => r_bus_in_keep,
                    dev_in_latch => r_bus_in_latch,
                    dev_out_cmd => s_bus_out_cmd,   --  output command
                    dev_out_addr => s_bus_out_addr, --  output address
                    dev_out_data => s_bus_out_data, --  output data
                    dev_out_drdy => s_bus_out_drdy, --  when new data arrives
                    dev_out_done => s_bus_out_done, --  when no more transactions
                    dev_err => s_bus_err,           --  if an error occurrs
                    dev_chg => s_bus_chg            --  when an operation on local physical registers completes
                );

    --  sampler
    SAMPLER:    process(sysClk)
                begin
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_bus_out_drdy <= '0';
                                ss_bus_out_done <= '0';
                                ss_bus_err <= '0';
                                ss_bus_chg <= '0';
                                ss_drdy <= '0';
                            
                            when s_PRE_0 =>
                                ss_drdy <= drdy;
                            
                            when s_IDLE =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_chg <= s_bus_chg;
                                ss_drdy <= drdy;
                            
                            when s_PORT_1 =>
                                ss_drdy <= drdy;
                            
                            when s_REG_0 =>
                                ss_bus_chg <= s_bus_chg;
                            
                            when s_VRT_1 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_VRT_2 =>
                                ss_drdy <= drdy;
                            
                            when s_VRT_3 =>
                                ss_drdy <= drdy;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
        
    --  main
    MAIN:       process(sysClk)
                    variable evts: std_logic_vector(2 downto 0) := "000";
                    variable addr: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_dack <= '0';
                                    r_ddir <= '0';
                                    r_bus_in_cmd <= '0';
                                    r_bus_in_addr <= (others=>'0');
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_keep <= '0';
                                    r_bus_in_latch <= '0';
                                    r_flag <= '0';
                                    r_stage <= s_PRE_0;
                                
                                when s_PRE_0 =>
                                    if (ss_drdy='0') then
                                        --  pre-initialization
                                        r_dack <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_dack <= '1';
                                        r_stage <= s_PRE_0;
                                    end if;
                                
                                when s_IDLE =>
                                    evts := (ss_bus_out_drdy & ss_bus_chg & ss_drdy);
                                    case (evts) is
                                        when "001" =>
                                            --  event on the port
                                            if (r_flag='0') then
                                                r_stage <= s_PORT_0;
                                            else
                                                r_stage <= s_IDLE;
                                            end if;
                                            
                                        when "010" =>
                                            --  a local register has been written
                                            r_stage <= s_REG_0;
                                        
                                        when "100" =>
                                            --  event from the bus : virtual register operation
                                            r_stage <= s_VRT_0;
                                        
                                        --  valid concurrent
                                        when "011" =>
                                            r_stage <= s_REG_0;
                                        
                                        when "101" =>
                                            r_stage <= s_VRT_0;

                                        when others =>
                                            r_stage <= s_IDLE;
                                    end case;
                                
                                --  port
                                when s_PORT_0 =>
                                    --  retaining new data
                                    r_data_to <= s_data_from;
                                    r_flag <= '1';
                                    r_stage <= s_IDLE;
                                
                                when s_PORT_1 =>
                                    if (ss_drdy='0') then
                                        r_dack <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_dack <= '1';
                                        r_stage <= s_PORT_1;
                                    end if;
                                                                                                                                                                                                                                        
                                --  local registers ignored
                                when s_REG_0 =>
                                    if (ss_bus_chg='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_REG_0;
                                    end if;
                                
                                --  virtual register: let's see if it is the flag checking or the data request
                                when s_VRT_0 =>
                                    addr := to_integer(unsigned(s_bus_out_addr)) - 64;
                                    case (addr) is
                                        when 0 =>
                                            --  new data flag
                                            r_bus_in_data(7 downto 1) <= (others=>'0');
                                            r_bus_in_data(0) <= r_flag;
                                            r_stage <= s_VRT_1;
                                        
                                        when 1 =>
                                            --  new data read
                                            r_bus_in_data <= r_data_to;
                                            r_flag <= '0';
                                            r_stage <= s_VRT_1;
                                        
                                        when 2 =>
                                            --  send data over to the port
                                            r_data_to <= s_bus_out_data;
                                            r_ddir <= '1';
                                            r_stage <= s_VRT_2;
                                                                                   
                                        when others =>
                                            r_bus_in_data <= x"00";
                                            r_stage <= s_VRT_1;
                                            
                                    end case;
                                
                                when s_VRT_1 =>
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        if (r_flag='0') then
                                            r_stage <= s_PORT_1;
                                        else
                                            r_stage <= s_IDLE;
                                        end if;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_VRT_1;
                                    end if;
                                
                                when s_VRT_2 =>
                                    if (ss_drdy='1') then
                                        r_dack <= '0';
                                        r_stage <= s_VRT_3;
                                    else
                                        r_dack <= '1';
                                        r_stage <= s_VRT_2;
                                    end if;
                                
                                when s_VRT_3 =>
                                    if (ss_drdy='0') then
                                        --  data received
                                        r_ddir <= '0';
                                        r_data_to <= (others=>'0');
                                        r_stage <= s_VRT_1;
                                    else
                                        --  waiting
                                        r_stage <= s_VRT_3;
                                    end if;
                            
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
    
end Behavioral;
