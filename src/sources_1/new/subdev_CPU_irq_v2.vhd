library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity subdev_CPU_irq_v2 is
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
        local_mem_begin: integer := 0;          --  start of memory space
        local_mem_nvrt: integer := 0;           --  number of virtual registers
        sram_mem_begin: integer := 0;           --  start of sram range (lies outside of the local memory range defined above)
        sram_mem_end: integer := 0;             --  end of sram range
        regcfg: string := "cpu_registers.mem";  --  logical registers configuration file
        isrcfg: string := "cpu_isrlut.mem";
        n_irq_lines: natural := 8;
        --  settings
        reset_vector: natural := 0
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
        --  booking
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;        --  this line will go high if the system bus has been granted
        bus_err_sys: in std_logic;
        --  hardware lines
        irq_lines: in std_logic_vector(n_irq_lines-1 downto 0);
        irq_grant: out std_logic_vector(n_irq_lines-1 downto 0);
        --  minibus
        irq_vector_bus: out std_logic_vector(31 downto 0);
        irq_vector_drdy: out std_logic;
        irq_vector_done: out std_logic;
        irq_vector_ack: in std_logic;
        --  sync signals for ISR progress
        irq_active: in std_logic;
        irq_active_wait: out std_logic;
        irq_prepare: out std_logic;
        --  debug
        dbg: out natural;
        dbg_isr: out natural
    );
end subdev_CPU_irq_v2;

architecture Behavioral of subdev_CPU_irq_v2 is
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
    signal ss_bus_out_cmd: std_logic := '0';        
    signal ss_bus_out_drdy: std_logic := '0';
    signal ss_bus_out_done: std_logic := '0';
    signal ss_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal ss_bus_err: std_logic := '0';
    signal ss_bus_chg: std_logic := '0';
    
    --  output drivers
    signal r_irq_grant: std_logic_vector(n_irq_lines-1 downto 0) := (others=>'0');
    signal r_irq_drdy: std_logic := '0';
    signal r_irq_done: std_logic := '0';
    signal r_irq_bus: std_logic_vector(31 downto 0) := (others=>'0');
    signal r_irq_prepare: std_logic := '0';
    
    --  sampling interrupts
    signal ss_irq_lines: std_logic_vector(n_irq_lines-1 downto 0) := (others=>'0');
    signal irq_flag: std_logic;
    signal ss_irq_flag: std_logic;
    signal ss_irq_ack: std_logic;
    signal ss_irq_active: std_logic;
    signal r_irq_active_wait: std_logic := '0';
    
    --  interrupt data
    type isr_data is array (0 to 7) of std_logic_vector(31 downto 0);
    signal isr_file: isr_data;
    
    --  LUT for the ISR entry points
    --  function to load up the ISR look up table
    type isrlut_type is array (0 to 31) of std_logic_vector(23 downto 0);
    impure function init_isrlut return isrlut_type is 
      file text_file : text open read_mode is isrcfg;
      variable text_line : line;
      variable ram_content : isrlut_type;
      variable bv : bit_vector(ram_content(0)'range);
    begin
      for i in 0 to 31 loop
        readline(text_file, text_line);
        read(text_line, bv);
        ram_content(i) := to_stdlogicvector(bv);
      end loop;
      return ram_content;
    end function;
    --  loading up the interrupt service routine lookup table
    signal isr_lut: isrlut_type := init_isrlut;
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_IRH_0, s_IRH_1, s_IRH_1b, s_IRH_2, s_IRH_3, s_IRH_4, s_IRH_5, s_IRH_6, s_IRH_7, s_IRH_8, s_IRH_WAIT_0, s_IRH_WAIT_1);
    signal r_stage: t_SM := s_INIT;
    
    --  debug
    signal r_dbg: natural := 0;
    
    --  synchro
    signal ss_sync_0: std_logic := '0';
begin
    --  assignments for output drive
    irq_vector_bus <= r_irq_bus;
    irq_vector_drdy <= r_irq_drdy;
    irq_vector_done <= r_irq_done;
    irq_active_wait <= r_irq_active_wait;
    irq_prepare <= r_irq_prepare;
    irq_grant <= r_irq_grant;
    dbg <= r_dbg;
    
    --  irq flag
    irq_flag <= (irq_lines(0) or irq_lines(1) or irq_lines(2) or irq_lines(3) or irq_lines(4) or irq_lines(5) or irq_lines(6) or irq_lines(7));  

    SBUSINT:    entity work.subbus_dev_v2(Behavioral)
                generic map (
                    dev_id => dev_id,
                    local_mem_begin => local_mem_begin,
                    local_mem_nvrt => local_mem_nvrt
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
                    dev_chg => s_bus_chg            --  when an operation on local physical registers completes
                );
 
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_irq_lines <= (others=>'0');
                                ss_irq_flag <= '0';
                                ss_bus_out_drdy <= '0';
                                ss_irq_ack <= '0';
                                ss_irq_active <= '0';
                                ss_sync_0 <= '0';
                            
                            when s_IDLE =>
                                ss_irq_lines <= irq_lines;
                                ss_irq_flag <= irq_flag;
                                ss_sync_0 <= '1';
                            
                            when s_IRH_WAIT_0 =>
                                ss_irq_ack <= irq_vector_ack;
                            
                            when s_IRH_WAIT_1 =>
                                ss_irq_ack <= irq_vector_ack;
                            
                            when s_IRH_0 =>
                                ss_sync_0 <= '0';
                            
                            when s_IRH_1 =>
                                ss_sync_0 <= '1';
                                ss_irq_lines <= irq_lines;
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_data <= s_bus_out_data;
                            
                            when s_IRH_1b =>
                                ss_sync_0 <= '0';
                            
                            when s_IRH_2 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_IRH_5 =>
                                ss_irq_ack <= irq_vector_ack;
                            
                            when s_IRH_6 =>
                                ss_irq_ack <= irq_vector_ack;
                            
                            when s_IRH_7 =>
                                ss_irq_active <= irq_active;
                            
                            when s_IRH_8 =>
                                ss_irq_active <= irq_active;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
 
    MAIN:       process(sysClk)
                    variable e: natural := 0;
                    variable f0: natural := 0;
                    variable f1: natural := 0;
                    variable h: natural := 0;
                    variable ha: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_irq_grant <= (others=>'0');
                                    r_irq_bus <= (others=>'0');
                                    r_irq_drdy <= '0';
                                    r_irq_done <= '0';
                                    r_irq_active_wait <= '0';
                                    r_irq_prepare <= '0';
                                    r_dbg <= 0;
                                    --  going
                                    r_stage <= s_IDLE;
                                                                
                                when s_IDLE =>
                                    r_dbg <= 1;
                                    if ((ss_sync_0='1') and (ss_irq_flag='1')) then
                                        e := 0;
                                        r_stage <= s_IRH_0;
                                    else
                                        r_stage <= s_IDLE;
                                    end if;
                                
                                when s_IRH_0 =>
                                    r_dbg <= 2;
                                    --  searching for the source of the interrupt
                                    if (ss_irq_lines(e)='1') then
                                        --  found it
                                        f0 := 0;
                                        f1 := 0;
                                        r_stage <= s_IRH_WAIT_0;
                                    else
                                        --  still searching
                                        e := e + 1;
                                        r_stage <= s_IRH_0;
                                    end if;
                                
                                when s_IRH_WAIT_0 =>
                                    r_dbg <= 3;
                                    --  we must ask the CPU to stop while we consider this request
                                    if (ss_irq_ack='1') then
                                        --r_irq_prepare <= '0';
                                        r_stage <= s_IRH_WAIT_1;
                                    else
                                        r_irq_prepare <= '1';
                                        r_stage <= s_IRH_WAIT_0;
                                    end if;
                                
                                when s_IRH_WAIT_1 =>
                                    r_dbg <= 4;
                                    if (ss_irq_ack='0') then
                                        r_stage <= s_IRH_1;
                                    else
                                        --  moved this down from up to better synchronize signal changes
                                        r_irq_prepare <= '0';
                                        r_stage <= s_IRH_WAIT_1;
                                    end if;
                                    
                                when s_IRH_1 =>
                                    r_dbg <= 5;
                                    if (ss_sync_0='1') then
                                        --  checking
                                        r_stage <= s_IRH_1b;
                                    else
                                        --  waiting
                                        r_stage <= s_IRH_1;
                                    end if;
                                
                                when s_IRH_1b =>
                                    if (ss_irq_lines(e)='0') then
                                        --   no more
                                        if (f1=0) then
                                            f0 := f0;
                                        else
                                            f0 := f0+1;
                                        end if;
                                        r_stage <= s_IRH_3;
                                    else
                                        if (ss_bus_out_drdy='1') then
                                            --  we have the interrupt vector data!
                                            isr_file(f0)(((f1+1)*8)-1 downto (f1*8)) <= ss_bus_out_data;
                                            r_stage <= s_IRH_2;
                                        else
                                            --  waiting for the interrupt vector data
                                            r_irq_grant(e) <= '1';
                                            r_stage <= s_IRH_1;
                                        end if;
                                    end if;
                                
                                when s_IRH_2 =>
                                    r_dbg <= 6; -- ok devo togliere 64                                                                                                     
                                    if (ss_bus_out_drdy='0') then
                                        r_bus_in_latch <= '0';
                                        if (f1=3) then
                                            f1 := 0;
                                            f0 := f0 + 1;
                                        else
                                            f1 := f1 + 1;
                                            f0 := f0;
                                        end if;
                                        r_stage <= s_IRH_1;
                                    else
                                        --  waiting
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_IRH_2;
                                    end if;
                                
                                when s_IRH_3 =>
                                    r_dbg <= 7;
                                    f1 := 0;
                                    r_stage <= s_IRH_3;
                                    --  going now through the look-up table to assemble the final words
                                    --  the first word will contain the program counter, hence:
                                    h := to_integer(unsigned(isr_file(0)(4 downto 0)));
                                    ha := isr_file(0)(27 downto 5);
                                    dbg_isr <= to_integer(unsigned(ha));
                                    --  saving the new program counter into word 0
                                    isr_file(0)(addr_width-1 downto 0) <= isr_lut(h)(addr_width-1 downto 0);
                                    isr_file(0)(31 downto addr_width) <= (others=>'0');
                                    --  reshaping the first argument so that now it only contains its address and not also the pointer
                                    isr_file(1)(addr_width-1 downto 0) <= ha;
                                    isr_file(1)(31 downto addr_width) <= (others=>'0');
                                    -- now we can output all the words
                                    r_stage <= s_IRH_4;
                                
                                when s_IRH_4 =>
                                    r_dbg <= 8;
                                    r_irq_bus <= isr_file(f1);
                                    if (f1=f0) then
                                        r_irq_done <= '1';
                                    else
                                        r_irq_done <= '0';
                                    end if;
                                    r_stage <= s_IRH_5;
                                
                                when s_IRH_5 =>
                                    r_dbg <= 9;
                                    if (ss_irq_ack='1') then
                                        r_stage <= s_IRH_6;
                                    else
                                        r_irq_drdy <= '1';
                                        r_stage <= s_IRH_5;
                                    end if;
                                
                                when s_IRH_6 =>
                                    r_dbg <= 10;
                                    if (ss_irq_ack='0') then
                                        if (f1=f0) then
                                            --  we have sent everything
                                            f1 := 0;
                                            f0 := 0;
                                            r_stage <= s_IRH_7;
                                        else
                                            --  we have more to send
                                            f1 := f1 + 1;
                                            r_stage <= s_IRH_4;
                                        end if;
                                    else
                                        r_irq_drdy <= '0';
                                        r_irq_done <= '0';
                                        r_stage <= s_IRH_6;
                                    end if;
                                
                                when s_IRH_7 =>
                                    r_dbg <= 11;
                                    if (ss_irq_active='1') then
                                        r_irq_active_wait <= '1';
                                        r_stage <= s_IRH_8;
                                    else
                                        r_stage <= s_IRH_7;
                                    end if;
                                
                                when s_IRH_8 =>
                                    r_dbg <= 12;
                                    --  we wait for the cpu to complete the ISR before re-enabling the interrupts on the calling device
                                    if (ss_irq_active='0') then
                                        --  the cpu has completed, so
                                        r_irq_active_wait <= '0';
                                        r_irq_grant(e) <= '0';
                                        if (e=(n_irq_lines-1)) then
                                            e := 0;
                                        else
                                            e := e + 1;
                                        end if;
                                        r_stage <= s_IDLE;
                                    else
                                        --  waiting for the cpu
                                        r_stage <= s_IRH_8;
                                    end if;
                                                                
                            end case;
                        end if;
                    end if;
                end process MAIN;    
    
end Behavioral;
