library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  this subdev belongs to the 'UART subsystem'. Hence it has a subbus_dev interface to the sub-bus bridge
--  and a connection to the hardware bus. This wraps around 'subbus_dev'.
--  this module must be instantiated inside the 'dev_UART' where the bus_bridge resides and also the hwdrv_UART
entity subdev_UART_dev0_v2 is
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
        cpu_irq_addr: natural := 0;
        ISR_0_pointer: natural := 0
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  sub-system signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  booking signals
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;          --  this line will go high if the system bus has been granted
        bus_err_sys: in std_logic;          --  this line will go high if booking fails
        --  irq lines
        irq_line: out std_logic;
        irq_grant: in std_logic;
        --  hardware databus lanes
        hw_bus_rq: out std_logic;
        hw_bus_grant: in std_logic;
        hw_bus_busy: in std_logic;
        hw_data_to: out std_logic_vector(data_width-1 downto 0);
        hw_keep: out std_logic;
        hw_latch: out std_logic;
        hw_done: in std_logic;
        hw_data_from: in std_logic_vector(data_width-1 downto 0);
        hw_drdy: in std_logic;
        hw_ack: out std_logic;
        hw_tns: inout std_logic;
        --  debug
        dbg_main: out natural;
        dbg_subbus: out natural;
        dbg_subbus_dev: out natural;
        dbg_subbus_dev_int: out natural
    );
end subdev_UART_dev0_v2;

architecture Behavioral of subdev_UART_dev0_v2 is
    --  subdev interface
    signal r_bus_in_cmd: std_logic := '0';
    signal r_bus_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_in_keep: std_logic := '0';
    signal r_bus_in_latch: std_logic := '0';
    
    --  samplig hw bus
    signal ss_hw_bus_grant: std_logic := '0';
    signal ss_hw_bus_busy: std_logic := '0';
    signal ss_hw_done: std_logic := '0';
    signal ss_hw_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal ss_hw_drdy: std_logic := '0';
    
    --  sampling sub-bus
    signal s_bus_out_cmd: std_logic;
    signal s_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_bus_out_drdy: std_logic;
    signal s_bus_out_done: std_logic;
    signal s_bus_err: std_logic;
    signal s_bus_chg: std_logic;
    signal ss_bus_out_cmd: std_logic := '0';
    --signal ss_bus_out_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal ss_bus_out_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal ss_bus_out_drdy: std_logic := '0';
    signal ss_bus_out_done: std_logic := '0';
    signal ss_bus_err: std_logic := '0';
    signal ss_bus_chg: std_logic := '0';
    
    --  hardware bus drivers
    signal r_hw_bus_dir: std_logic := '0';
    signal r_hw_bus_rq: std_logic := '0';
    signal r_hw_bus_data_to: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_hw_bus_keep: std_logic := '0';
    signal r_hw_bus_latch: std_logic := '0';
    signal r_hw_bus_ack: std_logic := '0';
    signal r_hw_bus_dir_bak: std_logic := '0';
    
    --  tns line
    signal r_hw_bus_tns: std_logic := '0';
    signal s_hw_bus_tns: std_logic;
    signal ss_hw_bus_tns: std_logic;
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_LREG_0, s_VREG_0, s_VREG_1,s_VREG_2, s_VREG_3, s_VREG_4, s_VREG_5, s_VREG_6, s_HW_0, s_HW_1, s_HW_2, s_HW_3, s_HW_4, s_HW_5, s_HW_6, s_HW_7, s_HW_8, s_ERR);
    signal r_stage: t_SM := s_INIT;
    signal r_hw_stage: t_SM := s_HW_0;
    signal r_hw_stage_2: t_SM := s_HW_0;
    
    --  input data register
    signal r_uart_data: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_irq_data: std_logic_vector(31 downto 0) := (others=>'0');
    signal r_nof_bytes: std_logic_vector(23 downto 0) := (others=>'0');
    
    signal r_dbg: natural := 0;
    signal r_dbg_sbus: natural := 0;
    signal r_dbg_dev: natural := 0;
    signal r_dbg_devbus: natural;
     
    signal r_irq: std_logic := '0';
    signal ss_irq_grant: std_logic;
    
    --  synchronizer
    signal ss_sync_0: std_logic := '0';
    
   
begin
    --  debug signals 
    dbg_main <= r_dbg;
    dbg_subbus <= r_dbg_sbus;
    dbg_subbus_dev <= r_dbg_dev;
    dbg_subbus_dev_int <= r_dbg_devbus;
    
    --  shared lines drivers for hardware driver
    HWBUS_DATA_DRV: entity work.buffer_nbits(Behavioral) generic map (w => 8) port map(d => r_hw_bus_data_to, q => hw_data_to, oe=>r_hw_bus_dir);
    HWBUS_KEEP_DRV: entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_keep, q(0) => hw_keep, oe=>r_hw_bus_dir);
    HWBUS_LATCH_DRV:entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_latch, q(0) => hw_latch, oe=>r_hw_bus_dir);
    HWBUS_ACK_DRV:  entity work.buffer_nbits(Behavioral) generic map (w => 1) port map(d(0) => r_hw_bus_ack, q(0) => hw_ack, oe=>r_hw_bus_dir);
    --  tns inout
    HWBUS_TNS_DRV:  entity work.inout_port(Behavioral) generic map (nbits => 1) port map(io(0) => hw_tns, data_to(0) => r_hw_bus_tns, data_from(0) => s_hw_bus_tns, dir => r_hw_bus_dir);

    --  continuous assignment
    hw_bus_rq <= r_hw_bus_rq;
    irq_line <= r_irq;

    --  subbus to interface with the central system
    SBUSINT:    entity work.subbus_dev_v2(Behavioral)
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
                    bus_done_S => bus_done_S,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  addendum for the sub-dev
                    bus_req_sys => bus_req_sys,
                    bus_rdy_sys => bus_rdy_sys,
                    bus_err_sys => bus_err_sys,
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
                    dev_chg => s_bus_chg,           --  when an operation on local physical registers completes
                    --  debug
                    dbg_stage => r_dbg_sbus,
                    dbg_trx_stage => r_dbg_dev,
                    dbg_devbus => r_dbg_devbus
                );
            
    --  main sampling and driving processes: this processese listens for bus and hardware events and acts accordingly
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                -- sub-bus
                                ss_bus_out_cmd <= '0';
                                --ss_bus_out_addr <= (others=>'0');
                                ss_bus_out_data <= (others=>'0');
                                ss_bus_out_drdy <= '0';
                                ss_bus_out_done <= '0';
                                ss_bus_err <= '0';
                                ss_bus_chg <= '0';
                                --  so
                                ss_irq_grant <= '0';
                                ss_bus_out_drdy <= '0';
                                --  hardware bus
                                ss_hw_bus_grant <= '0';
                                ss_hw_bus_busy <= '0';
                                ss_hw_done <= '0';
                                ss_hw_data_from <= (others=>'0');
                                ss_hw_drdy <= '0';
                                --  synchro
                                ss_sync_0 <= '0';
                            
                            when s_IDLE =>
                                ss_bus_out_cmd <= s_bus_out_cmd;
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_data <= s_bus_out_data;
                                ss_bus_chg <= s_bus_chg;
                                ss_hw_drdy <= hw_drdy;
                                ss_hw_data_from <= hw_data_from;
                                ss_irq_grant <= irq_grant;
                                ss_sync_0 <= '0';

                            when s_HW_1 =>
                                ss_hw_bus_tns <= s_hw_bus_tns;
                                
                            when s_HW_2 =>
                                ss_hw_bus_tns <= s_hw_bus_tns;
                            
                            when s_HW_3 =>
                                ss_hw_drdy <= hw_drdy;
                            
                            when s_HW_5 =>
                                ss_irq_grant <= irq_grant;
                            
                            when s_HW_7 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_err <= s_bus_err;
                            
                            when s_HW_8 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                                     
                            when s_LREG_0 =>
                                ss_bus_chg <= s_bus_chg;                                
                            
                            when s_VREG_0 =>
                                ss_hw_bus_grant <= hw_bus_grant;
                                ss_hw_bus_busy <= hw_bus_busy;
                                ss_bus_out_data <= s_bus_out_data;
                                ss_bus_out_done <= s_bus_out_done;
                                ss_sync_0 <= '1';
                            
                            when s_VREG_1 =>
                                ss_sync_0 <= '0';
                                ss_hw_done <= hw_done;
                            
                            when s_VREG_2 =>
                                ss_hw_done <= hw_done;
                            
                            when s_VREG_3 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_VREG_4 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_data <= s_bus_out_data;
                                ss_bus_out_done <= s_bus_out_done;
                            
                            when s_VREG_5 =>
                                ss_hw_bus_grant <= hw_bus_grant;
                                ss_hw_bus_busy <= hw_bus_busy;
                                ss_sync_0 <= '1';
                            
                            when s_VREG_6 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process(sysClk)
                    variable cond: std_logic_vector(2 downto 0) := "000";
                    variable cond_idle: std_logic_vector(3 downto 0) := "0000";
                    variable data: natural := 0;
                    variable c: natural := 0;
                    variable d: natural := 0;
                    variable hwc: std_logic_vector(1 downto 0) := "00";
                    variable hwlim: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    --  initializing hardware controls
                                    r_hw_bus_dir <= '0';
                                    r_hw_bus_rq <= '0';
                                    r_hw_bus_data_to <= (others=>'0');
                                    r_hw_bus_keep <= '0';
                                    r_hw_bus_latch <= '0';
                                    r_hw_bus_ack <= '0';
                                    r_hw_bus_tns <= '0';
                                    --  initializing bus controls
                                    r_bus_in_cmd <= '0';
                                    r_bus_in_addr <= (others=>'0');
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_keep <= '0';
                                    r_bus_in_latch <= '0';
                                    --  command stages
                                    r_hw_stage <= s_HW_0;
                                    r_hw_stage_2 <= s_IDLE;
                                    --  flags
                                    r_uart_data <= (others=>'0');
                                    r_irq_data <= (others=>'0');
                                    r_nof_bytes <= (others=>'0');
                                    --  added
                                    r_irq <= '0';
                                    data := 0;
                                    c := 0;
                                    d := 0;
                                    hwc := "00";
                                    hwlim := 0;
                                    --  going
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  now I need to poll both the sub-bus and the hardware bus for events
                                    r_dbg <= 255;
                                    --   no interrupt request in progress
                                    cond_idle := (ss_irq_grant & ss_bus_out_drdy & ss_bus_chg & ss_hw_drdy);
                                    case (cond_idle) is
                                        --  hardware event: must check if it is for us
                                        --  in every case, an input hardware event is considered ONLY if there are no
                                        --  ongoing interrupt requests from this device.
                                        when "0001" =>
                                            r_stage <= r_hw_stage;
                                        
                                        --  bus event: data was written/read from a base/logical register
                                        --  in case of concurrency with a hardware event, priority is given to physical event first
                                        when "0010" | "0011" | "1010" | "1011" =>
                                            r_stage <= s_LREG_0;
                                                                                
                                        --  bus event: data is arriving/requested to/from a virtual register
                                        --  in case of concurrency with a hardware event, priority is given to virtual event first
                                        when "0100" | "0101" | "1100" | "1101" =>
                                            r_stage <= s_VREG_0;
                                        
                                        --  state 000 is idle since no event occurrs
                                        --  states like 110 and 111 are not possible since the bus interface cannot
                                        --  generate both a virtual and physical register event at the same time
                                        when others =>
                                            r_stage <= s_IDLE;
                                        
                                    end case;
                                
                                when s_HW_0 =>
                                    --  checking the hardware event
                                    r_dbg <= 1;
                                    if (to_integer(unsigned(ss_hw_data_from))=hw_id) then
                                        --  the following bytes are for us, so we may activate the bus
                                        c := 0;
                                        hwc := "01";
                                        r_hw_bus_dir <= '1';
                                        r_hw_bus_tns <= '1';
                                        r_hw_stage <= s_HW_4;
                                        r_stage <= s_HW_3;
                                    else
                                        --  this is not for us, so
                                        hwc := "00";
                                        r_hw_bus_dir <= '0';
                                        r_stage <= s_HW_1;
                                    end if;
                                
                                when s_HW_1 =>
                                    r_dbg <= 2;
                                    if (ss_hw_bus_tns='1') then
                                        --  finally
                                        r_hw_stage <= s_HW_2;
                                        r_stage <= s_IDLE;
                                    else
                                        --  waiting here until the tns signal goes high
                                        r_stage <= s_HW_1;
                                    end if;
                                
                                when s_HW_2 =>
                                    --  waiting here for the hardware bus to finish
                                    r_dbg <= 3;
                                    if (ss_hw_bus_tns='0') then
                                        --  finished
                                        r_hw_stage <= s_HW_0;
                                        r_stage <= s_HW_0;
                                    else
                                        r_stage <= s_IDLE;
                                    end if;
                                
                                when s_HW_3 =>
                                    r_dbg <= 4;
                                    --  releasing the hardware lines
                                    if (ss_hw_drdy='0') then
                                        r_hw_bus_ack <= '0';
                                        r_stage <= r_hw_stage_2;
                                    else
                                        r_hw_bus_ack <= '1';
                                        r_stage <= s_HW_3;
                                    end if;
                                
                                when s_HW_4 =>
                                    r_dbg <= 5;
                                    --  i come here if it is for us
                                    case (hwc) is
                                        when "00" =>
                                            --  this is at the end of everything
                                            r_hw_bus_tns <= '0';
                                            r_hw_bus_dir <= '0';
                                            r_hw_stage <= s_HW_0;
                                            r_hw_stage_2 <= s_IDLE;
                                            r_stage <= s_IDLE;
                                        
                                        when "01" =>
                                            --  we're receiving now the number of bytes to be sent over
                                            r_nof_bytes(((c+1)*8)-1 downto (c*8)) <= ss_hw_data_from;
                                            if (c=2) then
                                                --  received all of the 3 bytes
                                                c := 0;
                                                hwlim := to_integer(unsigned(r_nof_bytes));
                                                hwc := "10";
                                            else
                                                --  must go again
                                                c := c + 1;
                                                hwc := "01";
                                            end if;
                                            --  going
                                            r_stage <= s_HW_3;
                                        
                                        when "10" =>
                                            --  we are now receiving the data bytes from the uart -> for each of these, I need to fire an interrupt
                                            r_uart_data <= ss_hw_data_from;
                                            c := c + 1;
                                            r_stage <= s_HW_5;
                                        
                                        when "11" =>
                                            --  we have sent everything for the IRQ, so now we have to wait for the cpu to complete its request
                                            r_irq <= '0';
                                            if (c=hwlim) then
                                                --  no more do to for this uart transaction -> must free
                                                hwc := "00";
                                                c := 0;
                                                --  going
                                                r_hw_stage_2 <= s_HW_4;
                                                r_stage <= s_HW_3;
                                            else
                                                --  still have bytes for the uart
                                                hwc := "10";
                                                r_stage <= s_HW_3;
                                            end if;
                                        
                                        when others =>
                                            null;
                                    end case;
                                
                                when s_HW_5 =>
                                    r_dbg <= 6;
                                    --  firing the interrupt now
                                    if (ss_irq_grant='1') then
                                        --  we can send over the details of the ISR we want the cpu to run
                                        --  the ISR is identified by a 5 bit pointer. In our case ISR_0 is pointer 0
                                        --  then the ISR_0 requires a single argument, that is our virtual address from which to read the single byte
                                        --  so we need to send over 23 + 5 = 28 bits
                                        d := 0;
                                        r_irq_data(4 downto 0) <= std_logic_vector(to_unsigned(ISR_0_pointer, 5));
                                        r_irq_data(27 downto 5) <= std_logic_vector(to_unsigned(local_mem_begin+64, addr_width));
                                        r_irq_data(31 downto 28) <= (others=>'0');
                                        r_stage <= s_HW_6;
                                    else
                                        --  waiting for the CPU to stop and acknowledge our request
                                        r_irq <= '1';
                                        r_stage <= s_HW_5;
                                    end if;
                                
                                when s_HW_6 =>
                                    r_dbg <= 7;
                                    r_bus_in_cmd <= '0';
                                    r_bus_in_addr <= std_logic_vector(to_unsigned(cpu_irq_addr, addr_width));
                                    r_bus_in_data <= r_irq_data(((d+1)*8)-1 downto (d*8));
                                    if (d=3) then
                                        r_bus_in_keep <= '0';
                                    else
                                        r_bus_in_keep <= '1';
                                    end if;
                                    r_stage <= s_HW_7;
                                
                                when s_HW_7 =>
                                    r_dbg <= 8;
                                    cond := '0'&ss_bus_out_drdy&ss_bus_err;
                                    case (cond) is
                                        when "000" =>
                                            --  waiting
                                            r_bus_in_latch <= '1';
                                            r_stage <= s_HW_7;
                                        
                                        when "001" =>
                                            --  error
                                            r_stage <= s_ERR;
                                        
                                        when "010" =>
                                            --  success
                                            r_stage <= s_HW_8;
                                        
                                        when others =>
                                            --  illegal conition
                                            r_stage <= s_HW_7;
                                    end case;
                                
                                when s_ERR =>
                                    r_dbg <= 170;
                                    r_stage <= s_ERR;
                                
                                when s_HW_8 =>
                                    r_dbg <= 9;
                                    if (ss_bus_out_drdy='0') then
                                        --  vedere
                                        if (d=3) then
                                            --  sent everything
                                            d := 0;
                                            hwc := "11";
                                            r_stage <= s_HW_4; 
                                        else
                                            --  still need to send
                                            d := d + 1;
                                            r_stage <= s_HW_6;
                                        end if;
                                    else
                                        --  waiting
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_HW_8;
                                    end if;
                                                                                         
                                when s_LREG_0 =>
                                    r_dbg <= 10;
                                    --  in this case, the register is signalling that a read/write operation has been
                                    --  performed on one of them, I need to act accordingly
                                    if (ss_bus_chg='0') then
                                        --  done
                                        r_bus_in_latch <= '0';
                                        r_stage <= r_hw_stage_2;
                                    else
                                        --  signalling ok
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_LREG_0;
                                    end if;
                                
                                when s_VREG_0 =>
                                    r_dbg <= 11;
                                    --  virtual register signals a command
                                    --  i can use virtual addresses to cover the whole ascii space
                                    --  i need to cover 127 codes and i start from address 64 onwards
                                    --  so: 64 to 191 inclusive signal the correct code to write
                                    --  so if I need to send character 65 ("A") i will send 65+64 = 129.
                                    --  first, I need to request the hardware bus in order to control the hardware transmitter
                                    if (ss_bus_out_cmd='1') then
                                        --  it is a read, in this case i don't have to act on the transmitter
                                        r_bus_in_data <= r_uart_data;
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_VREG_6;
                                    else
                                        --  it is a write, so we must access the hardware transmitter
                                        cond := ss_sync_0 & ss_hw_bus_grant & ss_hw_bus_busy;
                                        case (cond) is
                                            --  bus has been granted to us finally, so
                                            when "110" | "111" =>
                                                r_dbg <= to_integer(unsigned(ss_bus_out_data));
                                                r_hw_bus_data_to <= ss_bus_out_data;
                                                r_hw_bus_keep <= (not ss_bus_out_done);
                                                r_hw_bus_dir_bak <= r_hw_bus_dir;
                                                r_hw_bus_dir <= '1';
                                                r_stage <= s_VREG_1;
                                                                                    
                                            when others =>
                                                --  waiting, or the bus has not been given to us so I must wait to be serviced
                                                r_hw_bus_rq <= '1';
                                                r_stage <= s_VREG_0;
                                        end case;
                                    end if;
                                
                                when s_VREG_1 =>
                                    r_dbg <= 12;
                                    if (ss_hw_done='1') then
                                        --  the hardware transmitter has transmitted the data
                                        r_hw_bus_latch <= '0';
                                        r_stage <= s_VREG_2;
                                    else
                                        --  launching the data
                                        r_hw_bus_latch <= '1';
                                        r_stage <= s_VREG_1;
                                    end if;
                                
                                when s_VREG_2 =>
                                    r_dbg <= 13;
                                    if (ss_hw_done='0') then
                                        --  signalling the sub-bus we're ready for more or that we're done
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_VREG_3;
                                    else
                                        r_stage <= s_VREG_2;
                                    end if;
                                
                                when s_VREG_3 =>
                                    r_dbg <= 14;
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        --  checking the 'keep' signal
                                        if (r_hw_bus_keep='1') then
                                            --  the bus will send more, so:
                                            r_stage <= s_VREG_4;
                                        else
                                            --  we're finished, releasing the bus
                                            --  but wait because if an interrupt is in progress, if i disable the bus
                                            --  here, the HW interrupt won't be able to acknowledge, so, instead of disabling it,
                                            --  we restore the direction to the previous value.
                                            r_hw_bus_dir <= r_hw_bus_dir_bak;
                                            r_hw_bus_rq <= '0';
                                            r_stage <= s_VREG_5;
                                        end if;
                                    else
                                        r_stage <= s_VREG_3;
                                    end if;
                                
                                when s_VREG_4 =>
                                    r_dbg <= 15;
                                    if (ss_bus_out_drdy='1') then
                                        --  going with the new data
                                        r_hw_bus_data_to <= ss_bus_out_data;
                                        r_hw_bus_keep <= (not ss_bus_out_done);
                                        r_stage <= s_VREG_1;
                                    else
                                        r_stage <= s_VREG_4;
                                    end if;
                                
                                when s_VREG_5 =>
                                    r_dbg <= 16;
                                    if ((ss_sync_0='1') and (ss_hw_bus_grant='0') and (ss_hw_bus_busy='0')) then
                                        r_stage <= s_IDLE;
                                    else
                                        r_stage <= s_VREG_5;
                                    end if;
                                
                                when s_VREG_6 =>
                                    r_dbg <= 17;
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_stage <= s_VREG_6;
                                    end if;

                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
end Behavioral;
