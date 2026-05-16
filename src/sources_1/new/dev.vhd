library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
--  changelog 4/4/25
--  changed s_BUSEXT_i to avoid using double registry to mitigate negative slack
entity dev is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  device data
        dev_id: integer := 0;
        --  device memory range
        --  these addresses must be >= 0x20000
        dev_mem_begin: integer := 0;    --  start of memory address space
        dev_mem_end: integer := 0;      --  end of memory address space
        --  sram reserved memory
        --  this memory lies outside of the above mentioned space
        dev_phy_begin: integer := 0;    --  start of sram range
        dev_phy_end: integer := 0;      --  end of sram range
        --  register file configuration
        regcfg: string := "generic.mem" --  register file configuration memfile
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  bus interface signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  external interface signals
        dev_in_cmd: in std_logic;
        dev_in_addr: in std_logic_vector(addr_width-1 downto 0);
        dev_in_data: in std_logic_vector(data_width-1 downto 0);
        dev_in_latch: in std_logic;
        dev_in_keep: in std_logic;
        dev_out_cmd: out std_logic;
        dev_out_addr: out std_logic_vector(addr_width-1 downto 0);
        dev_out_data: out std_logic_vector(data_width-1 downto 0);
        dev_out_drdy: out std_logic;
        dev_out_done: out std_logic;
        dev_err: out std_logic;
        dev_chg: out std_logic;
        --  debug ports
        dbg_stage: out natural;
        dbg_reg_drdy: out std_logic;
        dbg_reg_done: out std_logic;
        dbg_bus_drdy: out std_logic;
        devbus_interface: out integer
    );
end dev;

architecture Behavioral of dev is
    --  some constants
    --  every device has 32 base registers (8 bit wide) + up to 32 logical registers (sub/combinations of base registers)
    --  by design, registers 0 to 31 are base registers while 32 to 63 are logical
    constant dev_reg_begin: integer := dev_mem_begin;
    constant dev_reg_end: integer := (dev_mem_begin+63);
    --  virtual addresses cover the remaining part of the memory space from dev_mem_begin+64 to dev_mem_end
    --  virtual addresses are specified in the device customization phase
    constant dev_vrt_begin: integer := (dev_mem_begin+64);
    constant dev_vrt_end: integer := dev_mem_end;
    
    --  EXT INTERFACE SIGNALS
    --  sampling signals
    signal s_dev_in_cmd: std_logic := '0';
    signal s_dev_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal s_dev_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal s_dev_in_latch: std_logic := '0';
    signal s_dev_in_keep: std_logic := '0';
        
    --  driving signals
    signal r_dev_out_cmd: std_logic := '0';
    signal r_dev_out_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_dev_out_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_dev_out_drdy: std_logic := '0';
    signal r_dev_out_done: std_logic := '0';
    signal r_dev_err: std_logic := '0';
    signal r_dev_chg: std_logic := '0';
                
    --  BUS INTERFACE SIGNALS
    --  sampling signals
    signal s_bus_command_from: std_logic := '0';
    signal s_bus_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal s_bus_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal s_bus_drdy: std_logic := '0';
    signal s_bus_done: std_logic := '0';
    signal ss_bus_command_from: std_logic := '0';
    signal ss_bus_address_from: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal ss_bus_data_from: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal ss_bus_drdy: std_logic := '0';
    signal ss_bus_done: std_logic := '0';
    signal ss_bus_ready: std_logic := '0';
    signal ss_bus_busy: std_logic := '0';
    --  driving signals
    signal r_bus_command_to: std_logic := '0';
    signal r_bus_address_to: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_latch: std_logic := '0';
    signal r_bus_ack: std_logic := '0';
    signal r_bus_keep: std_logic := '0';
    
    --  REGISTER FILE SIGNALS
    --  sampling signals
    signal s_reg_data_fr: std_logic_vector(data_width-1 downto 0) := (others=>'0');    
    signal s_reg_drdy: std_logic := '0';
    signal s_reg_done: std_logic := '0';
    signal ss_reg_data_fr: std_logic_vector(data_width-1 downto 0) := (others=>'0');    
    signal ss_reg_drdy: std_logic := '0';
    signal ss_reg_done: std_logic := '0';
    
    --  driving signals
    signal r_reg_data_to: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_reg_address: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_reg_cmd: std_logic := '0';
    signal r_reg_latch: std_logic := '0';
    
    --  STATE MACHINE
    type t_SM is (  s_INIT, s_IDLE, s_EXTERR_0, s_EXTREG_rw0, s_EXTREG_rw1,
                    s_EXTREG_w0, s_EXTREG_w1, s_EXTREG_w2, s_EXTREG_w3,
                    s_EXTREG_r0, s_EXTREG_r1, s_EXTREG_r2, s_EXTREG_r3,
                    s_EXTBUS_0, S_EXTBUS_1, s_EXTBUS_2, s_EXTBUS_3, s_EXTBUS_4_0, s_EXTBUS_4_1, s_EXTBUS_5,
                    s_BUSEXT_i, s_BUSEXT_0, s_BUSEXT_1, s_BUSEXT_2, s_BUSEXT_3, s_BUSEXT_4,
                    s_BUSVRT_0, s_BUSVRT_1, s_BUSVRT_2, s_BUSVRT_3
                 );
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    signal r_dbg_stage: natural := 0;
begin
    --  interface to the system bus
    DEV_BUS_INT:    entity work.bus_interface(Behavioral)
                        generic map (
                            bus_width => bus_width,
                            data_width => data_width,
                            addr_width => addr_width,
                            dev_mem_begin => dev_mem_begin,
                            dev_mem_end => dev_mem_end
                        ) port map (
                            sysClk => sysClk,
                            sysRstb => sysRstb,
                            --  bus lines
                            bus_lines => bus_lines,
                            bus_strobe_M => bus_strobe_M,
                            bus_strobe_S => bus_strobe_S,
                            bus_keep => bus_keep,
                            bus_rq => bus_rq,
                            bus_grant => bus_grant,
                            bus_busy => bus_busy,
                            --  interface
                            command_to => r_bus_command_to,
                            command_from => s_bus_command_from,
                            address_to => r_bus_address_to,
                            address_from => s_bus_address_from,
                            data_to => r_bus_data_to,
                            data_from => s_bus_data_from,
                            latch => r_bus_latch,
                            done => s_bus_done,
                            drdy => s_bus_drdy,
                            ack => r_bus_ack,
                            keep => r_bus_keep,
                            --  debug signal
                            dbg_stage => devbus_interface
                        );
    
    --  register file
    REG_FILE_INT:   entity work.regs(Behavioral)
                        generic map (
                            memfile => regcfg
                        ) port map (
                            sysClk => sysClk,
                            sysRstb => sysRstb,
                            --  stuff
                            r_cmd => r_reg_cmd,
                            r_address => r_reg_address,
                            r_data_to => r_reg_data_to,
                            r_data_fr => s_reg_data_fr,
                            latch_cmd => r_reg_latch,
                            drdy => s_reg_drdy,
                            done => s_reg_done
                        );
    
    --  sampler
    SAMPLER:    process (sysClk)
    
                begin
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                --  initialization stage
                                ss_bus_command_from <= '0';
                                ss_bus_address_from <= (others=>'0');
                                ss_bus_data_from <= (others=>'0');
                                ss_bus_drdy <= '0';
                                ss_bus_done <= '0';
                                --  reg
                                ss_reg_data_fr <= (others=>'0');
                                ss_reg_drdy <= '0';
                                ss_reg_done <= '0';
                                --  ext
                                s_dev_in_cmd <= '0';
                                s_dev_in_addr <= (others=>'0');
                                s_dev_in_data <= (others=>'0');
                                s_dev_in_latch <= '0';
                                s_dev_in_keep <= '0';
                          
                            when s_IDLE =>
                                --  we look for bus activation
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_data_from <= s_bus_data_from;
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_done <= s_bus_done;
                                ss_bus_ready <= bus_grant;
                                ss_bus_busy <= bus_busy;
                                --  and for external interface activity
                                s_dev_in_cmd <= dev_in_cmd;
                                s_dev_in_addr <= dev_in_addr;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_keep <= dev_in_keep;
                        
                            when s_EXTERR_0 =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_EXTREG_w1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                
                            when s_EXTREG_w2 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_EXTREG_w3 =>
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_keep <= dev_in_keep;
                            
                            when s_EXTREG_r1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                ss_reg_data_fr <= s_reg_data_fr;
                                
                            when s_EXTREG_r2 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_EXTREG_r3 =>
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_keep <= dev_in_keep;
                            
                            when s_EXTREG_rw0 =>
                                s_dev_in_cmd <= dev_in_cmd;
                                s_dev_in_addr <= dev_in_addr;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_keep <= dev_in_keep;
                        
                            when s_EXTBUS_1 =>
                                ss_bus_ready <= bus_grant;
                                ss_bus_busy <= bus_busy;
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_done <= s_bus_done;
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_data_from <= s_bus_data_from;
                        
                            when s_EXTBUS_2 =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_EXTBUS_3 =>
                                s_dev_in_latch <= dev_in_latch;
                                ss_bus_drdy <= s_bus_drdy;
                            
                            when s_EXTBUS_4_0 =>
                                ss_bus_drdy <= s_bus_drdy;
                            
                            when s_EXTBUS_4_1 =>
                                ss_bus_done <= s_bus_done;
                            
                            when s_EXTBUS_5 =>
                                s_dev_in_cmd <= dev_in_cmd;
                                s_dev_in_addr <= dev_in_addr;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_latch <= dev_in_latch;
                                s_dev_in_keep <= dev_in_keep;
                       
                            when s_BUSEXT_0 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                ss_reg_data_fr <= s_reg_data_fr;
                            
                            when s_BUSEXT_1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                ss_bus_drdy <= s_bus_drdy;
                            
                            when s_BUSEXT_2 =>
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_done <= s_bus_done;
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_data_from <= s_bus_data_from;
                            
                            when s_BUSEXT_3 =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_BUSEXT_4 =>
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_BUSVRT_0 =>
                                s_dev_in_cmd <= dev_in_cmd;
                                s_dev_in_addr <= dev_in_addr;
                                s_dev_in_data <= dev_in_data;
                                s_dev_in_keep <= dev_in_keep;
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_BUSVRT_1 =>
                                ss_bus_drdy <= s_bus_drdy;
                                s_dev_in_latch <= dev_in_latch;
                            
                            when s_BUSVRT_2 =>
                                ss_bus_drdy <= s_bus_drdy;
                                ss_bus_done <= s_bus_done;
                                ss_bus_command_from <= s_bus_command_from;
                                ss_bus_address_from <= s_bus_address_from;
                                ss_bus_data_from <= s_bus_data_from;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
   
    MAIN:       process (sysClk)
                    variable cond: std_logic_vector(1 downto 0) := "00";
                    variable check: std_logic_vector(2 downto 0) := "000";
                    variable addr: integer := 0;
                    variable test: std_logic_vector(2 downto 0) := "000";
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            --  reset
                            r_stage <= s_INIT;
                        else
                            --  case
                            case (r_stage) is
                                when s_INIT =>
                                    --  debug
                                    r_dbg_stage <= 0;
                                    --  ext
                                    r_dev_out_cmd <= '0';
                                    r_dev_out_addr <= (others=>'0');
                                    r_dev_out_data <= (others=>'0');
                                    r_dev_out_drdy <= '0';
                                    r_dev_out_done <= '0';
                                    r_dev_err <= '0';
                                    --  bus
                                    r_bus_command_to <= '0';
                                    r_bus_address_to <= (others=>'0');
                                    r_bus_data_to <= (others=>'0');
                                    r_bus_latch <= '0';
                                    r_bus_ack <= '0';
                                    r_bus_keep <= '0';
                                    --  reg
                                    r_reg_data_to <= (others=>'0');
                                    r_reg_address <= (others=>'0');
                                    r_reg_cmd <= '0';
                                    r_reg_latch <= '0';
                                    --  going
                                    r_stage <= s_IDLE;
                            
                                -----------------------------------------------------------------------------------------------------
                                --
                                --  IDLING
                                --
                                -----------------------------------------------------------------------------------------------------
                                when s_IDLE =>
                                    --  debug
                                    r_dbg_stage <= 1;
                                    --  idling
                                    cond := ss_bus_drdy & s_dev_in_latch;
                                    addr := to_integer(unsigned(s_dev_in_addr));
                                    case (cond) is
                                        when "10" =>
                                            --  in this case we have an event on the bus -> this gets the precedence over everything else of course
                                            --  now, when something arrives on the bus, there can be two situations:
                                            --  1) if the data is directed/requested from the base/logical registers, than everything occurrs without the
                                            --  device knowing. The device might be informed by a signal that gets pulled high to signal that an operation
                                            --  has occurred on that register.
                                            --  2) it the data is directed/requested from a virtual register, it must be forwarded to the device for proper
                                            --  handling.
                                            --  in this case this device will act as a SLAVE
                                            r_stage <= s_BUSEXT_i;
                                        when "11" =>
                                            --  like case "10"
                                            r_stage <= s_BUSEXT_i;
                                    
                                        when "01" =>
                                            --  in this case we have an event from the external interface
                                            --  in the case of a bus operation this device will act as a MASTER
                                            r_stage <= s_EXTREG_rw1;
                                        
                                        when others =>
                                            --  in all the other cases, we stay in idle
                                            r_stage <= s_IDLE; 
                                    end case;
                            
                                -----------------------------------------------------------------------------------------------------
                                --
                                --  EXT to REG and REG to EXT
                                --
                                -----------------------------------------------------------------------------------------------------
                                when s_EXTERR_0 =>
                                    --  debug
                                    r_dbg_stage <= 2;
                                    --  transaction not allowed, hence
                                    if (s_dev_in_latch='0') then
                                        r_dev_err <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_stage <= s_EXTERR_0;
                                    end if;
                                
                                --  EXT to REG write cycle
                                when s_EXTREG_w0 =>
                                    --  debug
                                    r_dbg_stage <= 3;
                                    --  write cycle onto the registers, so:
                                    addr := to_integer(unsigned(s_dev_in_addr));
                                    r_reg_cmd <= '0';
                                    r_reg_address <= std_logic_vector(to_unsigned(addr - dev_reg_begin, 8));
                                    r_reg_data_to <= s_dev_in_data;
                                    r_reg_latch <= '1';
                                    r_stage <= s_EXTREG_w1;
                                
                                when s_EXTREG_w1 =>
                                    --  debug
                                    r_dbg_stage <= 4;
                                    cond := ss_reg_drdy & ss_reg_done;
                                    case (cond) is                                        
                                        when "10" =>
                                            --  means that the byte has been written but there's still more writing to do
                                            r_reg_latch <= '0';
                                            r_dev_out_drdy <= '1';
                                            r_dev_out_done <= '0';
                                            r_jump <= s_EXTREG_w3;
                                            r_stage <= s_EXTREG_w2;
                                        
                                        when "11" =>
                                            --  means that the byte has been written and it was also the very last to be written so
                                            r_reg_latch <= '0';
                                            r_dev_out_drdy <= '1';
                                            r_dev_out_done <= '1';
                                            if (s_dev_in_keep='1') then
                                                --  multiple commands required
                                                r_jump <= s_EXTREG_rw0;
                                            else
                                                r_jump <= s_IDLE;
                                            end if;
                                            r_stage <= s_EXTREG_w2;
                                    
                                        when others =>
                                            --  waiting
                                            r_stage <= s_EXTREG_w1;
                                    end case;
                                
                                when s_EXTREG_w2 =>
                                    --  debug
                                    test := s_dev_in_latch & ss_reg_drdy & ss_reg_done;
                                    r_dbg_stage <= to_integer(unsigned(test));
                                    if ((s_dev_in_latch='0') and (ss_reg_drdy='0') and (ss_reg_done='0')) then
                                        r_dev_out_drdy <= '0';
                                        r_dev_out_done <= '0';
                                        r_stage <= r_jump;
                                    else
                                        r_stage <= s_EXTREG_w2;
                                    end if;
                                
                                when s_EXTREG_w3 =>
                                    --  debug
                                    r_dbg_stage <= 6;
                                    if (s_dev_in_latch='1') then
                                        r_stage <= s_EXTREG_w0;
                                    else
                                        r_stage <= s_EXTREG_w3;
                                    end if;
                                
                                --  multiple commands
                                when s_EXTREG_rw0 =>
                                    --  debug
                                    r_dbg_stage <= 7;
                                    --  initial
                                    if (s_dev_in_latch='1') then
                                        --  we can go forward
                                        r_stage <= s_EXTREG_rw1;
                                    else
                                        --  waiting
                                        r_stage <= s_EXTREG_rw0;
                                    end if;
                                    
                                when s_EXTREG_rw1 =>
                                    --  debug
                                    r_dbg_stage <= 8;
                                    --  in this case we have that the external interface wants to write to multiple registers in one go, so
                                    addr := to_integer(unsigned(s_dev_in_addr));
                                    if ((addr >= dev_reg_begin) and (addr <= dev_reg_end)) then
                                        --  it is for the local registers, but virtual addresses are not allowed, so:
                                        if (addr <= dev_reg_end) then
                                            --  valid ext-register transaction
                                            if (s_dev_in_cmd='0') then
                                                --  write command
                                                r_stage <= s_EXTREG_w0;
                                            else
                                                --  read command
                                                r_stage <= s_EXTREG_r0;
                                            end if;
                                        else
                                            --  not a valid ext-register transaction
                                            r_dev_err <= '1';
                                            r_stage <= s_EXTERR_0;
                                        end if;
                                    else
                                        --  the target address lies outside this space, it needs to go to the bus, so we need to try to get the bus
                                        r_stage <= s_EXTBUS_0;
                                    end if;
                                
                                --  REG to EXT read cycle
                                when s_EXTREG_r0 =>
                                    --  debug
                                    r_dbg_stage <= 9;
                                    r_reg_cmd <= '1';
                                    r_reg_address <= std_logic_vector(to_unsigned(addr - dev_reg_begin, 8));
                                    r_reg_data_to <= (others=>'0');
                                    r_reg_latch <= '1';
                                    r_stage <= s_EXTREG_r1;
                                
                                when s_EXTREG_r1 =>
                                    --  debug
                                    r_dbg_stage <= 10;
                                    --  waiting for 'drdy' to go high, so
                                    cond := ss_reg_drdy & ss_reg_done;
                                    case (cond) is
                                        when "10" =>
                                            --  we've got a byte from the register but there's more
                                            r_reg_latch <= '0';
                                            r_dev_out_drdy <= '1';
                                            r_dev_out_done <= '0';
                                            r_dev_out_data <= ss_reg_data_fr;
                                            r_jump <= s_EXTREG_r3;
                                            r_stage <= s_EXTREG_r2;
                                        
                                        when "11" =>
                                            --  we've got the final byte from the register, no more
                                            r_reg_latch <= '0';
                                            r_dev_out_drdy <= '1';
                                            r_dev_out_done <= '1';
                                            r_dev_out_data <= ss_reg_data_fr;
                                            if (s_dev_in_keep='1') then
                                                --  multiple commands required
                                                r_jump <= s_EXTREG_rw0;
                                            else
                                                r_jump <= s_IDLE;
                                            end if;
                                            r_stage <= s_EXTREG_r2;
                                    
                                        when others =>
                                            --  waiting
                                            r_stage <= s_EXTREG_r1;
                                    end case;
                            
                                when s_EXTREG_r2 =>
                                    --  debug
                                    r_dbg_stage <= 11;
                                    if ((s_dev_in_latch='0') and (ss_reg_drdy='0') and (ss_reg_done='0')) then
                                        r_dev_out_drdy <= '0';
                                        r_dev_out_done <= '0';
                                        r_stage <= r_jump;
                                    else
                                        r_stage <= s_EXTREG_r2;
                                    end if;
                            
                                when s_EXTREG_r3 =>
                                    --  debug
                                    r_dbg_stage <= 12;
                                    --  preparing to fetch another byte from the register
                                    if (s_dev_in_latch='1') then
                                        r_stage <= s_EXTREG_r0;
                                    else
                                        r_stage <= s_EXTREG_r3;
                                    end if;
                                
                                -----------------------------------------------------------------------------------------------------
                                --
                                --  EXT to BUS : this basically acts as a passthrough
                                --
                                -----------------------------------------------------------------------------------------------------
                                when s_EXTBUS_0 =>
                                    --  debug
                                    r_dbg_stage <= 13;
                                    --  we compile the input in order to start a bus transaction, so:
                                    r_bus_command_to <= s_dev_in_cmd;
                                    r_bus_address_to <= s_dev_in_addr;
                                    r_bus_data_to <= s_dev_in_data;
                                    r_bus_keep <= s_dev_in_keep;
                                    --  latchint
                                    r_bus_latch <= '1';
                                    r_stage <= s_EXTBUS_1;
                            
                                                                                              
                                when s_EXTBUS_1 =>
                                    --  debug
                                    r_dbg_stage <= 14;
                                    --  now we must wait and see what happens
                                    check := ss_bus_ready & ss_bus_busy & ss_bus_drdy;
                                    case (check) is
                                        --  the bus has been given to somebody else, so we must release and go to idle
                                        when "010" =>
                                            r_dev_err <= '1';
                                            r_stage <= s_EXTERR_0;
                                        when "011" =>
                                            r_dev_err <= '1';
                                            r_stage <= s_EXTERR_0;
                                        
                                        when "101" =>
                                            --  we have the bus and the data is ready, so we may proceed gathering the response to the command
                                            --  we have to drive the ext outputs to present the data the bus sent us back
                                            r_dev_out_cmd <= ss_bus_command_from;
                                            r_dev_out_addr <= ss_bus_address_from;
                                            r_dev_out_data <= ss_bus_data_from;
                                            r_dev_out_drdy <= ss_bus_drdy;
                                            r_dev_out_done <= ss_bus_done;
                                            --  and now let's see                                            
                                            r_stage <= s_EXTBUS_2;
                                        when "111" =>
                                            --  we have the bus and the data is ready, so we may proceed gathering the response to the command
                                            --  we have to drive the ext outputs to present the data the bus sent us back
                                            r_dev_out_cmd <= ss_bus_command_from;
                                            r_dev_out_addr <= ss_bus_address_from;
                                            r_dev_out_data <= ss_bus_data_from;
                                            r_dev_out_drdy <= ss_bus_drdy;
                                            r_dev_out_done <= ss_bus_done;
                                            --  and now let's see                                            
                                            r_stage <= s_EXTBUS_2;
                                        
                                        when others =>
                                            --  we wait
                                            r_stage <= s_EXTBUS_1;
                                    end case;

                                when s_EXTBUS_2 =>
                                    --  debug
                                    r_dbg_stage <= 15;
                                    if (s_dev_in_latch='0') then
                                        --  the ext interface has ack-ed the data we sent, so
                                        r_dev_out_drdy <= '0';
                                        r_dev_out_done <= '0';
                                        r_bus_ack <= '1';
                                        --  and now we jump according to some things
                                        if (ss_bus_done='0') then
                                            --  it means that the remote device's response has yet more bytes, so
                                            r_stage <= s_EXTBUS_3;
                                        else
                                            --  it means that the remote device doesn't have to send us more data
                                            --  but we might have more transactions in mind, so
                                            if (s_dev_in_keep='1') then
                                                --  we have more transactions, so 
                                                --  in this case we have to wait for the ss_bus_drdy to go low, then lower ack and also lower the latch on the bus
                                                --  once this is done, the bus is ready to accept a new transaction
                                                r_bus_latch <= '0';
                                                r_jump <= s_EXTBUS_5;
                                            else
                                                --  no more transactions to do, we're done
                                                --  in this case we have as well to wait for ss_bus_drdy to go low, then lower ack and also lower the latch on the bus
                                                --  once this is done, the bus is freed and we have to terminate here also
                                                r_bus_latch <= '0';
                                                r_jump <= s_IDLE;
                                            end if;
                                            r_stage <= s_EXTBUS_4_0;
                                        end if;
                                    else
                                        r_stage <= s_EXTBUS_2;
                                    end if;
                            
                                when s_EXTBUS_3 =>
                                    --  debug
                                    r_dbg_stage <= 16;
                                    if ((s_dev_in_latch='1') and (ss_bus_drdy='0')) then
                                        --  now everything is ready for more things
                                        r_bus_ack <= '0';
                                        r_stage <= s_EXTBUS_1;
                                    else
                                        r_stage <= s_EXTBUS_3;
                                    end if;
                                
                                when s_EXTBUS_4_0 =>
                                    r_dbg_stage <= 100;
                                    if (ss_bus_drdy='0') then
                                        r_bus_ack <= '0';
                                        r_stage <= s_EXTBUS_4_1;
                                    else
                                        r_stage <= s_EXTBUS_4_0;
                                    end if;
                                
                                when s_EXTBUS_4_1 =>
                                    --  debug
                                    r_dbg_stage <= 17;
                                    if (ss_bus_done='0') then
                                        --  now, the bus is ready
                                        r_stage <= r_jump;
                                    else
                                        --  waiting for the bus
                                        r_stage <= s_EXTBUS_4_1;
                                    end if;
                            
                                when s_EXTBUS_5 =>
                                    --  debug
                                    r_dbg_stage <= 18;
                                    --  now we have to wait for the interface to start another transaction
                                    if (s_dev_in_latch='1') then
                                        --  new command to send
                                        r_stage <= s_EXTBUS_0;
                                    else
                                        --  waiting
                                        r_stage <= s_EXTBUS_5;
                                    end if;
                            
                                -----------------------------------------------------------------------------------------------------
                                --
                                --  BUS to EXT
                                --
                                -----------------------------------------------------------------------------------------------------
                                when s_BUSEXT_i =>
                                    --  debug
                                    r_dbg_stage <= 19;
                                    --  we have to check where this address is going
                                    addr := to_integer(unsigned(s_bus_address_from)); --to_integer(unsigned(ss_bus_address_from));
                                    --  adding now the flag to check whether ops from the bus to local registers are allowed
                                    if (addr <= dev_reg_end) then
                                        --  the bus wants to act on a base/logical register
                                        r_reg_cmd <= ss_bus_command_from;
                                        r_reg_address <= std_logic_vector(to_unsigned(addr - dev_reg_begin, 8));
                                        r_reg_data_to <= ss_bus_data_from;
                                        r_reg_latch <= '1';
                                        --  now we wait for the register file to do its thing
                                        r_stage <= s_BUSEXT_0;
                                    else
                                        --  it is a virtual register -> must forward everything to ext
                                        r_dev_out_cmd <= ss_bus_command_from;
                                        r_dev_out_addr <= std_logic_vector(to_unsigned(addr - dev_reg_begin, addr_width));
                                        r_dev_out_data <= ss_bus_data_from;
                                        r_dev_out_drdy <= ss_bus_drdy;
                                        r_dev_out_done <= ss_bus_done;
                                        r_stage <= s_BUSVRT_0;
                                    end if;
                            
                                when s_BUSEXT_0 =>
                                    --  debug
                                    r_dbg_stage <= 20;
                                    --  we have to wait for the register file to finish
                                    cond := ss_reg_drdy & ss_reg_done;
                                    case (cond) is
                                        when "10" =>
                                            --  it means it has finished writing, but that the logical register will require more to complete
                                            --  so the bus will need to supply more
                                            r_reg_latch <= '0';
                                            --  sending response to the master
                                            r_bus_command_to <= ss_bus_command_from;
                                            r_bus_address_to <= ss_bus_address_from;
                                            r_bus_data_to <= ss_reg_data_fr;
                                            --  setting the bus_keep according to the command
                                            if (ss_bus_command_from='0') then
                                                r_bus_keep <= '0';
                                            else
                                                r_bus_keep <= (not ss_reg_done);
                                            end if;
                                            --  latching the response to the bus
                                            r_bus_latch <= '1';
                                            --  setting the jump for next stage
                                            r_jump <= s_BUSEXT_2;
                                            r_stage <= s_BUSEXT_1;
                                    
                                        when "11" =>
                                            --  it means it has finished writing, but we must see if the bus has more transactions
                                            r_reg_latch <= '0';
                                            --  sending response to the master
                                            r_bus_command_to <= ss_bus_command_from;
                                            r_bus_address_to <= ss_bus_address_from;
                                            r_bus_data_to <= ss_reg_data_fr;
                                            r_bus_keep <= '0';
                                            --  latching response to the bus
                                            --r_bus_latch <= '1'; (edited 1)
                                            --  signalling the device of the action upon its register
                                            r_dev_out_cmd <= r_reg_cmd;
                                            r_dev_out_addr(addr_width-1 downto 8) <= (others=>'0');
                                            r_dev_out_addr(7 downto 0) <= r_reg_address;
                                            r_dev_out_data <= r_reg_data_to;
                                            r_dev_chg <= '1';
                                            --  setting the jump
                                            --r_jump <= s_BUSEXT_3;
                                            --r_stage <= s_BUSEXT_1;
                                            r_jump <= s_BUSEXT_1;
                                            r_stage <= s_BUSEXT_3;
                                        
                                        when others =>
                                            r_stage <= s_BUSEXT_0;
                                    end case;
                            
                                when s_BUSEXT_1 =>
                                    --  debug
                                    r_dbg_stage <= 21;
                                    --  need to wait
                                    if ((ss_reg_drdy='0') and (ss_reg_done='0') and (ss_bus_drdy='0')) then
                                        --  lowering the bus latch
                                        r_bus_latch <= '0';
                                        r_stage <= r_jump;
                                    else
                                        --  waiting
                                        r_stage <= s_BUSEXT_1;
                                    end if;
                            
                                when s_BUSEXT_2 =>
                                    --  debug
                                    r_dbg_stage <= 22;
                                    --  wait for the master to signal it's ready
                                    if (ss_bus_drdy='1') then
                                        --  going
                                        r_stage <= s_BUSEXT_i;
                                    else
                                        --  waitin
                                        r_stage <= s_BUSEXT_2;
                                    end if;
                            
                                when s_BUSEXT_3 =>
                                    --  debug
                                    r_dbg_stage <= 23;
                                    --  reg operation has finished, but we must see if the bus wants to do more transactions
                                    --  we must signal the device that data has been written on the register and before going further
                                    --  we must wait for the device to acknowledge it
                                    if (s_dev_in_latch='1') then
                                        --  the device has ack-ed the register change
                                        r_dev_chg <= '0';
                                        --  checking what to do now
                                        r_jump <= s_BUSEXT_4;
                                        --r_stage <= s_BUSEXT_4;
                                        r_bus_latch <= '1'; --  edited
                                        r_stage <= s_BUSEXT_1;
                                    else
                                        --  waiting
                                        r_stage <= s_BUSEXT_3;
                                    end if;
                                                                                                    
                                when s_BUSEXT_4 =>
                                    --  debug
                                    r_dbg_stage <= 24;
                                    --  then, let's see
                                    if (s_dev_in_latch='0') then
                                        if (ss_bus_done='1') then
                                            --  no more transactions
                                            r_stage <= s_IDLE;
                                        else
                                            --  must wait for another bus event
                                            r_stage <= s_BUSEXT_2;
                                        end if;
                                    else
                                        --  waiting
                                        r_stage <= s_BUSEXT_4;
                                    end if;
                            
                                when s_BUSVRT_0 =>
                                    --  debug
                                    r_dbg_stage <= 25;
                                    --  we must wait for the external interface to act in some fashion
                                    if (s_dev_in_latch='1') then
                                        --  sending the response to the bus
                                        r_bus_command_to <= s_dev_in_cmd;
                                        r_bus_address_to <= s_dev_in_addr;
                                        r_bus_data_to <= s_dev_in_data;
                                        r_bus_keep <= s_dev_in_keep;
                                        --  latching response to the bus
                                        r_bus_latch <= '1';
                                        r_dev_out_drdy <= '0';
                                        r_dev_out_done <= '0';
                                        r_stage <= s_BUSVRT_1;
                                    else
                                        --  waiting for a response
                                        r_stage <= s_BUSVRT_0;
                                    end if;
                            
                                when s_BUSVRT_1 =>
                                    --  debug
                                    r_dbg_stage <= 26;
                                    --  we wait for the bus to ack the data we sent over
                                    if ((ss_bus_drdy='0') and (s_dev_in_latch='0')) then
                                        r_bus_latch <= '0';
                                        --  now to see what I have to do
                                        --  check if we have more bytes to send over the bus
                                        if (r_bus_keep='1') then
                                            --  indeed we have, so
                                            r_stage <= s_BUSVRT_2;
                                        else
                                            --  we don't, but let's see if the master has more for us
                                            if (ss_bus_done='1') then
                                                --  it doesn't, we can terminate
                                                r_stage <= s_IDLE;
                                            else
                                                --  it does, we must prepare for another
                                                r_stage <= s_BUSVRT_2;
                                            end if;
                                        end if;
                                    else
                                        --  waiting
                                        r_stage <= s_BUSVRT_1;
                                    end if;
                            
                                when s_BUSVRT_2 =>
                                    --  debug
                                    r_dbg_stage <= 27;
                                    --  waiting for the bus to be ready for another go
                                    if (ss_bus_drdy='1') then
                                        r_stage <= s_BUSEXT_i;
                                    else
                                        r_stage <= s_BUSVRT_2;
                                    end if;
                            
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;
    
    --  output assignments
    dbg_stage <= r_dbg_stage;
    dev_out_cmd <= r_dev_out_cmd;
    dev_out_addr <= r_dev_out_addr;
    dev_out_data <= r_dev_out_data;
    dev_out_drdy <= r_dev_out_drdy;
    dev_out_done <= r_dev_out_done;
    dev_err <= r_dev_err;
    dev_chg <= r_dev_chg;
    
    --  debug
    dbg_reg_drdy <= ss_reg_drdy;
    dbg_reg_done <= ss_reg_done;
    dbg_bus_drdy <= ss_bus_drdy;
    
end Behavioral;
--  ad esempio se dev_mem_begin fosse 0x20000 e dev_mem_end fosse 0x200ff:
--  reg_begin:  0x20000
--  reg_end:    0x2003f
--  vrt_begin:  0x20040
--  vrt_end:    0x200ff     avrei 192 registri virtuali (follia haha)
--  la eeprom ad esempio si puo' mappare in questo modo in via virtuale.
--  la eeprom ha 32 kbytes, quindi ha indirizzi da 0x0000 a 0x7fff
--  questi li prendo come indirizzi virtuali, cosi quando provo a leggere/scrivere da questi, si triggera l'operazione sull'i2c e tutto avviene in modo trasparente.
--  perfetto.
--  i registri fisici e logici sono di grande utilita' per esempio nella cpu e nel modulo della 'alu' anche per le varie operazioni logiche, o nel caso dell'uart per varie altre robe.

