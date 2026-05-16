library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  virtual registers in general:
--  0 : sets the contents of the port to be send over the device
--  1 : reads the new_data flag
--  2 : reads the data
--  3 : sets the data direction for each data pin
entity subdev_GPIO_dev0 is
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
        --  hardware lines
        extport: inout std_logic_vector(data_width-1 downto 0);
        strobe_S: in std_logic;
        strobe_M: out std_logic
    );
end subdev_GPIO_dev0;

architecture Behavioral of subdev_GPIO_dev0 is    
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
    
    --  sampling signals for the bus interface
    signal ss_bus_out_drdy: std_logic;
    signal ss_bus_out_done: std_logic;
    signal ss_bus_err: std_logic;
    signal ss_bus_chg: std_logic;
    
    --  flag
    signal r_flag: std_logic := '0';
    signal r_data: std_logic_vector(data_width-1 downto 0);
    
    --  state machine for the main process
    type t_SM is (s_INIT, s_IDLE, s_PORT_0, s_PORT_1, s_PORT_2, s_REG_0, s_VRT_0, s_VRT_1, s_VRT_2, s_VRT_3, s_PRE_0, s_POST_0);
    signal r_stage: t_SM := s_INIT;
    
    --  control signals for the hardware port    
    signal r_data_to_port: std_logic_vector(data_width-1 downto 0);
    signal s_data_from_port: std_logic_vector(data_width-1 downto 0);
    signal r_port_dir: std_logic_vector(data_width-1 downto 0);
            
    --  state machine for the delay timer
    type t_SM_timer is (s_INIT_t, s_IDLE_t, s_0_t, s_1_t);
    signal r_stage_t: t_SM_timer := s_INIT_t;
    
    --  MAIN vs TIMER synchronization signals
    --  canAct signal that is being driven by the timer
    signal canAct: std_logic := '0';
    --  acted signal that is being driven by the main
    signal acted: std_logic := '0';
    
    --  strobing
    signal r_strobe_M: std_logic := '0';
    signal ss_strobe_S: std_logic;
    
begin
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

    --  hardware driver for the ports
    genloop_PORTS: for i in 0 to 7 generate
        PORTDRV_i: entity work.inout_port(Behavioral) generic map (nbits => 1) port map (io(0) => extport(i), data_to(0) => r_data_to_port(i), data_from(0) => s_data_from_port(i), dir=>r_port_dir(i));
    end generate genloop_PORTS;
    
    --  sampler
    SAMPLER:    process(sysClk)
                begin
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                
                        end case;
                    end if;
                end process SAMPLER;
    
    --  port hardware driver (goes with configurable speed)
    MAIN:       process(sysClk)
                    variable cond: std_logic_vector(3 downto 0) := "0000";
                    variable addr: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else                        
                            case (r_stage) is
                                when s_INIT =>
                                    r_port_dir <= (others=>'0');
                                    r_data_to_port <= (others=>'0');
                                    acted <= '0';
                                    r_stage <= s_PRE_0;
                                
                                --  syncing the external device
                                when s_PRE_0 =>
                                    if (ss_strobe_S='0') then
                                        r_strobe_M <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_strobe_M <= '1';
                                        r_stage <= s_PRE_0;
                                    end if;
                                
                                --  syncing with the timer
                                when s_POST_0 =>
                                    if (canAct='0') then
                                        acted <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        acted <= '1';
                                        r_stage <= s_POST_0;
                                    end if;
                                
                                when s_IDLE =>
                                    --  waiting for something to happen, so
                                    cond := (canAct & ss_bus_chg & ss_bus_out_drdy & ss_strobe_S);
                                    case (cond) is
                                        when "1001" =>
                                            --  we can act and we have to sample the device
                                            r_port_dir <= (others=>'0');
                                            r_stage <= s_PORT_0;
                                        
                                        when "1010" =>
                                            --  data incoming from virtual registers
                                            r_stage <= s_VRT_0;
                                        
                                        when "1011" =>
                                            --  virtual register + device trying to write
                                            r_stage <= s_VRT_0;
                                        
                                        when "1100" =>
                                            --  read/write from/to one of the base/logical registers
                                            r_stage <= s_REG_0;
                                        
                                        when "1101" =>
                                            --  read/write from/to base/logical registers + external device trying to write 
                                            r_stage <= s_REG_0;
                                                                                                                        
                                        when others =>
                                            --  in all of the other cases, we have to just wait here
                                            r_stage <= s_IDLE;                                            
                                    end case;
                            
                                --  handling device reading
                                when s_PORT_0 =>
                                    --  reading incoming data from the connected device
                                    r_data <= s_data_from_port;
                                    r_stage <= s_PORT_1;
                                
                                when s_PORT_1 =>
                                    if (ss_strobe_S='0') then
                                        r_strobe_M <= '0';
                                        r_stage <= s_POST_0;
                                    else
                                        r_strobe_M <= '1';
                                        r_stage <= s_PORT_1;
                                    end if;
                            
                                --  hanndling registers
                                when s_REG_0 =>
                                    if (ss_bus_chg='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_POST_0;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_REG_0;
                                    end if;
                            
                                --  handling virtual registers
                                when s_VRT_0 =>
                                    addr := to_integer(unsigned(s_bus_out_addr)) - 64;
                                    case (addr) is
                                        when 0 =>
                                            --  data to send over to the device
                                            r_data_to_port <= s_bus_out_data;
                                            r_stage <= s_VRT_2;
                                        
                                        when 1 =>
                                            --  reads the newdata flag
                                            if (r_flag='0') then
                                                r_bus_in_data <= std_logic_vector(to_unsigned(0, data_width));
                                            else
                                                r_bus_in_data <= std_logic_vector(to_unsigned(1, data_width));
                                            end if;
                                            r_stage <= s_VRT_1;
                                        
                                        when 2 =>
                                            --  gets the data from the buffer
                                            r_bus_in_data <= r_data;
                                            r_stage <= s_VRT_1;
                                        
                                        when 3 =>
                                            --  sets the data direction for the various pins
                                            r_port_dir <= s_bus_out_data;
                                            r_stage <= s_VRT_1;
                                        
                                        when others =>
                                            --  invalid operation
                                            r_stage <= s_VRT_1;
                                    end case;
                            
                                when s_VRT_1 =>
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_POST_0;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_VRT_1;
                                    end if;
                                
                                when s_VRT_2 =>
                                    if (ss_strobe_S='1') then
                                        r_strobe_M <= '0';
                                        r_stage <= s_VRT_3;
                                    else
                                        r_strobe_M <= '1';
                                        r_stage <= s_VRT_2;
                                    end if;
                                
                                when s_VRT_3 =>
                                    if (ss_strobe_S='0') then
                                        r_stage <= s_POST_0;
                                    else
                                        r_stage <= s_VRT_3;
                                    end if;                                
                                    
                            end case;
                        end if;
                    end if;
                end process MAIN;

    --  timer process that coordinates the sampling of the port
    TIMER:      process(sysClk)
                    variable c: natural := 0;
                begin
                    if (falling_edge(sysClk)) then
                        case (r_stage_t) is
                            when s_INIT_t =>
                                c := 0;
                                canAct <= '0';
                                r_stage_t <= s_IDLE_t;
                            
                            when s_IDLE_t =>
                                if (c=(delay-1)) then
                                    c:= 0;
                                    r_stage_t <= s_0_t;
                                else
                                    c := c + 1;
                                    r_stage_t <= s_IDLE_t;
                                end if;
                            
                            when s_0_t =>
                                if (acted='1') then
                                    canAct <= '0';
                                    r_stage_t <= s_1_t;
                                else
                                    canAct <= '1';
                                    r_stage_t <= s_0_t;
                                end if;
                            
                            when s_1_t =>
                                if (acted='0') then
                                    r_stage_t <= s_IDLE_t;
                                else
                                    r_stage_t <= s_1_t;
                                end if;                           
                                
                        end case;
                    end if;
                end process TIMER;

    --  hardware drivers
    strobe_M <= r_strobe_M;
    
end Behavioral;
