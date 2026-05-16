library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity cpu_IRH is
    generic (
        n_irq_lines: natural := 8;
        isrcfg: string := "cpu_isrlut.mem";
        addr_width: natural := 23;
        data_width: natural := 8
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  interrupt lines
        irq_lines: in std_logic_vector(n_irq_lines-1 downto 0);
        irq_grant: out std_logic_vector(n_irq_lines-1 downto 0);
        --  cpu bus access
        bus_in_cmd: out std_logic;
        bus_in_addr: out std_logic_vector(addr_width-1 downto 0);
        bus_in_data: out std_logic_vector(data_width-1 downto 0);
        bus_in_keep: out std_logic;
        bus_in_latch: out std_logic;
        bus_out_drdy: in std_logic;
        bus_out_done: in std_logic;
        bus_out_data: in std_logic_vector(data_width-1 downto 0);
        --  cpu synchronization
        irq_presence: out std_logic;
        irq_ack: in std_logic;
        --  isr output
        isr_output: out std_logic_vector(31 downto 0);
        isr_drdy: out std_logic;
        isr_done: out std_logic;
        isr_get: in std_logic
    );
end cpu_IRH;

architecture Behavioral of cpu_IRH is
    --  facility to store interrupt vector data
    type isr_data is array (0 to 5) of std_logic_vector(31 downto 0);
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
    
    --  irq flag to detect interrupts
    signal irq_flag: std_logic := '0';
    
    --  IRQ related signals
    signal r_irq_grant: std_logic_vector(n_irq_lines-1 downto 0) := (others=>'0');
    signal s_irq_lines: std_logic_vector(n_irq_lines-1 downto 0);
    signal ss_irq_flag: std_logic;
    signal ss_irq_lines: std_logic_vector(n_irq_lines-1 downto 0);
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s0, s1, s2, s3, s4, s5, s6, s7);
    signal r_stage: t_SM := s_INIT;
    
    --  outputs
    signal r_irq_presence: std_logic := '0';
    
    --  subdev interface
    signal r_bus_in_cmd: std_logic := '0';
    signal r_bus_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_in_keep: std_logic := '0';
    signal r_bus_in_latch: std_logic := '0';
    
    --  pc out
    signal r_isr_output: std_logic_vector(31 downto 0) := (others=>'0');
    signal r_isr_drdy: std_logic := '0';
    signal r_isr_done: std_logic := '0';
begin
    --  assignments
    irq_grant <= r_irq_grant;
    irq_presence <= r_irq_presence;
    bus_in_cmd <= r_bus_in_cmd;
    bus_in_addr <= r_bus_in_addr;
    bus_in_data <= r_bus_in_data;
    bus_in_keep <= r_bus_in_keep;
    bus_in_latch <= r_bus_in_latch;
    isr_output <= r_isr_output;
    isr_drdy <= r_isr_drdy;
    isr_done <= r_isr_done;
    
    --  irq lines OR-rer
    irq_flag <= (irq_lines(0) or irq_lines(1) or irq_lines(2) or irq_lines(3) or irq_lines(4) or irq_lines(5) or irq_lines(6) or irq_lines(7));
    
    MAIN:   process(sysClk)
                variable e: natural := 0;
                variable f0: natural := 0;
                variable f1: natural := 0;
            begin
                if (falling_edge(sysClk)) then
                    case (r_stage) is
                        when s_INIT =>
                            r_irq_grant <= (others=>'0');
                            r_irq_presence <= '0';
                            r_bus_in_cmd <= '0';
                            r_bus_in_data <= (others=>'0');
                            r_bus_in_addr <= (others=>'0');
                            r_bus_in_keep <= '0';
                            r_bus_in_latch <= '0';
                            r_isr_output <= (others=>'0');
                            r_isr_drdy <= '0';
                            r_isr_done <= '0';
                            e := 0;
                            f0 := 0;
                            f1 := 0;
                            --  going
                            r_stage <= s_IDLE;
                        
                        when s_IDLE =>
                            --  now to wait for an interrupt to appear
                            if (irq_flag='1') then
                                r_stage <= s0;
                            else
                                r_stage <= s_IDLE;
                            end if;
                        
                        when s0 =>
                            --  check who sent it
                            if (irq_lines(e)='1') then
                                --  found it, must now ask the cpu to stop
                                r_irq_presence <= '1';
                                r_stage <= s1;
                            else
                                e := e + 1;
                                r_stage <= s0;
                            end if;
                        
                        when s1 =>
                            --  waiting for the cpu
                            if (irq_ack='1') then
                                --  now the cpu has stopped, and is waiting for us
                                f0 := 0;
                                f1 := 0;
                                --  signalling that we will now proceed
                                r_irq_presence <= '0';
                                r_stage <= s2;
                            else
                                --  waiting
                                r_stage <= s1;
                            end if;
                        
                        when s2 =>
                            --  gathering the interrupt vector
                            if (irq_lines(e)='0') then
                                --  this interrupt vector is complete
                                f1 := 0;
                                r_stage <= s4;
                            else
                                if (bus_out_drdy='1') then
                                    --  device is sending the interrupt vector
                                    isr_file(f0)(((f1+1)*8)-1 downto (f1*8)) <= bus_out_data;
                                    r_stage <= s3;
                                else
                                    --  waiting for the device to send the interrupt vector
                                    r_irq_grant(e) <= '1';
                                    r_stage <= s2;
                                end if;
                            end if;
                        
                        when s3 =>
                            --  telling the device we've acknowledged it
                            if (bus_out_drdy='0') then
                                --  acknowledged the read, now:
                                r_bus_in_latch <= '0';
                                if (f1=3) then
                                    f1 := 0;
                                    f0 := f0 + 1;
                                else
                                    f1 := f1 + 1;
                                    f0 := f0;
                                end if;
                                r_stage <= s2;
                            else
                                --  acknowledging the read
                                r_bus_in_latch <= '1';
                                r_stage <= s3;
                            end if;
                        
                        when s4 =>
                            --  we have the whole interrupt vector, so I can output it to the cpu
                            r_irq_presence <= '1';
                            if (isr_get='1') then
                                r_stage <= s5;
                            else
                                r_isr_output <= isr_file(f1);
                                r_isr_drdy <= '1';
                                if (f1=f0) then
                                    r_isr_done <= '1';
                                else
                                    r_isr_done <= '0';
                                end if;
                                r_stage <= s4;
                            end if;
                        
                        when s5 =>
                            if (isr_get='0') then
                                if (f1=f0) then
                                    --  sent everything
                                    f1 := 0;
                                    f0 := 0;
                                    --  going
                                    r_stage <= s6;
                                else
                                    --  still need to send
                                    f1 := f1 + 1;
                                    r_stage <= s4;
                                end if;
                            else
                                r_isr_drdy <= '0';
                                r_isr_done <= '0';
                                r_stage <= s5;
                            end if;
                        
                        when s6 =>
                            --  signalling to the cpu that it can now proceed
                            if (irq_ack='0') then
                                -- the cpu has terminated the ISR execution
                                --  re-enabling interrupts on the device
                                r_irq_grant(e) <= '0';
                                --  telling the cpu it can now get the bus back
                                r_irq_presence <= '0';
                                r_stage <= s7;
                            else
                                --  telling the cpu that it can proceed
                                r_stage <= s6;
                            end if;
                        
                        when s7 =>
                            if (e=(n_irq_lines-1)) then
                                e := 0;
                            else
                                e := e +1;
                            end if;
                            r_stage <= s_IDLE;
                        
                        when others =>
                            r_stage <= s_IDLE;
                            
                    end case;
                end if;
            end process MAIN;
end Behavioral;


