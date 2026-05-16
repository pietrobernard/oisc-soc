library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  SUPER DEVICE is the supervisor. This device initializes the system and displays on the lcd the status messages
--  during this phase. Basically, the system starts and it is possible to do two things:
--  program the eeprom
--  initialize the system
--
--  when the system is initialized, the whole eeprom is copied in the sram in the first 32 kilobytes.
--  an idea I have could be to store some kind of "base program" in the eeprom that is put on the reset-vector.
--  and when that program runs, I can pause it, load a custom program in some region of the sram and then resume
--  and jump to that region to execute the program as if it were some kind of "function" that gets specified.
--  that I could do.
--
--  so this supervisor should be able to pause, resume and reset the cpu by accessing the control switches on the front
--  panel and the status leds.
--  
--  vediamo allora la struttura:
--  quando il sistema si attiva, ci puo' fare scegliere se caricare la eeprom in sram o se programmarla.
entity dev_SUPER is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  devices
        i2c_lcd_base: natural := 164362;
        i2c_eeprom_base: natural := 131529;
        --  device manager setup
        dev_id: integer := 3;
        dev_mem_begin: integer := 0;    --  start of memory space for the UART device
        dev_mem_end: integer := 0       --  end of memory space for the UART device                        
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  system bus interface signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  control signals for the cpu
        cpuctrl_run: out std_logic;
        cpuctrl_reset: out std_logic;
        cpuctrl_halt: in std_logic;
        cpu_output_port: in natural;
        --  front panel leds
        fp_green_led: out std_logic;
        fp_red_led: out std_logic;
        --  uart 0 irq
        uart_irq_0: in std_logic;
        uart_irq_grant_0: out std_logic;
        --  front panel switches and leds
        fp_switches: in std_logic_vector(1 downto 0);
        fp_leds: out std_logic_vector(7 downto 0)        
    );
end dev_SUPER;

architecture Behavioral of dev_SUPER is
    --  control registers
    signal r_dev_in_cmd: std_logic := '0';
    signal r_dev_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_dev_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_dev_in_keep: std_logic := '0';
    signal r_dev_in_latch: std_logic := '0';
    
    -- output signals from bus interface
    signal s_dev_out_cmd: std_logic;
    signal s_dev_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_dev_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_dev_out_drdy: std_logic;
    signal s_dev_out_done: std_logic;
    signal s_dev_err: std_logic;
    signal s_dev_chg: std_logic;
    
    --  sampling signals
    signal ss_dev_out_cmd: std_logic;
    signal ss_dev_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal ss_dev_out_data: std_logic_vector(data_width-1 downto 0);
    signal ss_dev_out_drdy: std_logic;
    signal ss_dev_out_done: std_logic;
    signal ss_dev_err: std_logic;
    signal ss_dev_chg: std_logic;
    
    --  stage
    type t_SM is (s_INIT, s_IDLE, s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20, s21, s22, s23, s24, s25, s26, s27, s28, s29, s30);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    --  drivers
    signal r_cpuctrl_run: std_logic := '0';
    signal r_cpuctrl_reset: std_logic := '0';
    signal r_front_red: std_logic := '0';
    signal r_front_green: std_logic := '0';
    signal r_uart_irq_grant_0: std_logic := '0';
    signal r_fp_leds: std_logic_vector(7 downto 0) := (others=>'0');
    
    --  samplers
    signal ss_uart_irq_0: std_logic := '0';
    signal ss_sync_0: std_logic := '0';
    
    --  display
    type t_Memory is array (0 to 184) of std_logic_vector(7 downto 0);
    --  eeprom menu: yes / no
    signal r_Mem_0 : t_Memory := (x"45",x"45",x"50",x"52",x"4f",x"4d",x"20",x"50",
                                x"52",x"4f",x"47",x"52",x"41",x"4d",x"3f",x"0a",
                                x"31",x"2e",x"20",x"59",x"65",x"73",x"0a",x"32",
                                x"2e",x"20",x"4e",x"6f",x"0a",x"43",x"68",x"6f",
                                x"69",x"63",x"65",x"3a",x"20",
                                --  eeprom waiting for data
                                x"45",x"45",x"50",x"52",x"4f",x"4d",x"20",x"50",
                                x"52",x"4f",x"47",x"52",x"41",x"4d",x"0a",x"57",
                                x"61",x"69",x"74",x"69",x"6e",x"67",x"20",x"66",
                                x"6f",x"72",x"20",x"64",x"61",x"74",x"61",x"2e",
                                x"2e",x"2e",x"0a",x"20",x"20",
                                --  sram menu
                                x"53",x"52",x"41",x"4d",x"20",x"50",x"52",x"4f",
                                x"47",x"52",x"41",x"4d",x"3f",x"0a",x"31",x"2e",
                                x"20",x"59",x"65",x"73",x"0a",x"32",x"2e",x"20",
                                x"4e",x"6f",x"0a",x"43",x"68",x"6f",x"69",x"63",
                                x"65",x"3a",x"20",x"20",x"20",
                                --  sram waiting for data
                                x"53",x"52",x"41",x"4d",x"20",x"50",x"52",x"4f",
                                x"47",x"52",x"41",x"4d",x"0a",x"57",x"61",x"69",
                                x"74",x"69",x"6e",x"67",x"20",x"66",x"6f",x"72",
                                x"20",x"64",x"61",x"74",x"61",x"2e",x"2e",x"2e",
                                x"0a",x"20",x"20",x"20",x"20",
                                --  final message
                                x"43",x"50",x"55",x"20",x"69",x"73",x"20",x"72",
                                x"65",x"61",x"64",x"79",x"21",x"0a",x"20",x"20",
                                x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
                                x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
                                x"20",x"20",x"20",x"20",x"20"
                                );
                                
    --  packets
    signal isr_packet: std_logic_vector(31 downto 0);    
    signal sram_packet: std_logic_vector(31 downto 0);
begin
    BUS_DEV:    entity work.dev_v2(Behavioral)
                generic map (
                    dev_id => dev_id,
                    dev_mem_begin => dev_mem_begin,
                    dev_mem_end => dev_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_done_S => bus_done_S,
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
                    dev_chg => s_dev_chg
                );

    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_sync_0 <= '0';
                            
                            when s1 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s2 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s4 =>
                                ss_uart_irq_0 <= uart_irq_0;
                            
                            when s5 =>
                                ss_sync_0 <= '1';
                                ss_dev_out_drdy <= s_dev_out_drdy;
                                ss_dev_out_data <= s_dev_out_data;
                            
                            when s6 =>
                                ss_sync_0 <= '0';
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s7 =>
                                ss_sync_0 <= '1';
                                ss_uart_irq_0 <= uart_irq_0;
                            
                            when s8 =>
                                ss_sync_0 <= '0';
                                ss_dev_out_drdy <= s_dev_out_drdy;
                                ss_dev_out_data <= s_dev_out_data;
                            
                            when s9 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s16 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s17 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s19 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s20 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s27 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when s28 =>
                                ss_dev_out_drdy <= s_dev_out_drdy;
                            
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process(sysClk)
                    variable c: natural := 0;
                    variable bc: natural := 0;
                    variable target_bc: natural := 0;
                    variable msg_begin: natural := 0;
                    variable msg_end: natural := 0;
                    variable addr: natural := 0;
                    variable n: natural := 0;
                    variable code: std_logic_vector(7 downto 0);
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_cpuctrl_run <= '0';
                                    r_cpuctrl_reset <= '0';
                                    r_front_green <= '0';
                                    r_front_red <= '0';
                                    c := 0;
                                    bc := 0;
                                    target_bc := 0;
                                    msg_begin := 0;
                                    msg_end := 0;
                                    code := x"23";
                                    r_uart_irq_grant_0 <= '0';
                                    r_jump <= s9;
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  devo attendere qualche ciclo di clock
                                    if (c=2999999) then
                                        c := 0;
                                        r_stage <= s10;
                                    else
                                        c := c + 1;
                                        r_stage <= s_IDLE;
                                    end if;
                                
                                --  THIS SENDS A MESSAGE TO THE LCD
                                when s0 =>
                                    r_dev_in_cmd <= '0';
                                    r_dev_in_addr <= std_logic_vector(to_unsigned(i2c_lcd_base + 4,23));
                                    r_dev_in_data <= r_Mem_0(c);
                                    if (c=msg_end) then
                                        r_dev_in_keep <= '0';
                                    else
                                        r_dev_in_keep <= '1';
                                    end if;
                                    r_stage <= s1;
                                
                                when s1 =>
                                    if (ss_dev_out_drdy='1') then
                                        r_stage <= s2;
                                    else
                                        r_dev_in_latch <= '1';
                                        r_stage <= s1;
                                    end if;
                                
                                when s2 =>
                                    if (ss_dev_out_drdy='0') then
                                        if (c=msg_end) then
                                            c := 0;
                                            r_stage <= r_jump;
                                        else
                                            c := c + 1;
                                            r_stage <= s0;
                                        end if;
                                    else
                                        r_dev_in_latch <= '0';
                                        r_stage <= s2;
                                    end if;
                                
                                --  THIS CLEARS THE LCD
                                when s3 =>
                                    r_dev_in_cmd <= '0';
                                    r_dev_in_addr <= std_logic_vector(to_unsigned(i2c_lcd_base + 0,23));
                                    r_dev_in_data <= x"00";
                                    r_dev_in_keep <= '0';
                                    c := 0;
                                    msg_end := 0;
                                    r_stage <= s1;
                                
                                --  THE FOLLOWING LINES CAPTURE A GIVEN NUMBER OF BYTES FROM THE UART_0 DEVICE                                
                                when s4 =>
                                    if (ss_uart_irq_0='1') then
                                        c := 0;
                                        r_uart_irq_grant_0 <= '1';
                                        r_stage <= s5;
                                    else
                                        r_uart_irq_grant_0 <= '0';
                                        r_stage <= s4;
                                    end if;
                                
                                when s5 =>
                                    if ((ss_sync_0='1') and (ss_dev_out_drdy='1')) then
                                        --  data is here
                                        isr_packet(((c+1)*8)-1 downto (c*8)) <= ss_dev_out_data;
                                        r_stage <= s6;
                                    else
                                        --  waiting for the ISR data
                                        r_stage <= s5;
                                    end if;
                                
                                when s6 =>
                                    if (ss_dev_out_drdy='0') then
                                        r_dev_in_latch <= '0';
                                        if (c=3) then
                                            --  it was the last one
                                            c := 0;
                                            r_stage <= s7;
                                        else
                                            --  still need to receive
                                            c := c + 1;
                                            r_stage <= s5;
                                        end if;
                                    else
                                        r_dev_in_latch <= '1';
                                        r_stage <= s6;
                                    end if;
                                
                                --  now we have the ISR data, so we can now read from it
                                when s7 =>
                                    if ((ss_sync_0='1') and (ss_uart_irq_0='0')) then
                                        --  it has lowered it, so we can now read the interrupt byte from it
                                        r_dev_in_cmd <= '1';
                                        r_dev_in_addr <= isr_packet(27 downto 5);
                                        r_dev_in_data <= (others=>'0');
                                        r_dev_in_keep <= '0';
                                        r_stage <= s8;
                                    else
                                        --  waiting for the device to lower its irq line
                                        r_stage <= s7;
                                    end if;
                                
                                when s8 =>
                                    if (ss_dev_out_drdy='1') then
                                        --  device has responded with the data I need, so:
                                        sram_packet(((bc+1)*8)-1 downto (bc*8)) <= ss_dev_out_data;
                                        r_stage <= s9;
                                    else
                                        --  waiting
                                        r_dev_in_latch <= '1';
                                        r_stage <= s8;
                                    end if;
                                
                                when s9 =>
                                    if (ss_dev_out_drdy='0') then
                                        --  check how many so that we can write to the SRAM
                                        if (bc=(target_bc-1)) then
                                            --  gathered everything -> we can return
                                            bc := 0;
                                            r_stage <= r_jump;
                                        else
                                            --  still need to gather before returning
                                            r_uart_irq_grant_0 <= '0';
                                            bc := bc + 1;                                    
                                            r_stage <= s4;
                                        end if;
                                    else
                                        --  waiting
                                        r_dev_in_latch <= '0';
                                        r_stage <= s9;
                                    end if;
                                
                                --  STAGES
                                when s10 =>
                                    --  now, we can display the first message on the LCD
                                    r_jump <= s11;
                                    msg_begin := 0;
                                    msg_end := 36;
                                    c := 0;
                                    r_stage <= s0;
                                
                                when s11 =>
                                    r_front_green <= '1';
                                    r_front_red <= '1';
                                    r_stage <= s11;
                                
                                when others =>
                                    r_stage <= s_INIT;
                                
--                                when s11 =>
--                                    --  the message has been shown, now need to wait for the uart input
--                                    r_jump <= s12;
--                                    bc := 0;
--                                    target_bc := 1;
--                                    r_stage <= s4;
                                
--                                when s12 =>
--                                    --  now the data we retrieved is stored in 'sram_packet'
--                                    if (sram_packet(7 downto 0)=x"49") then
--                                        --  we need to do eeprom programming
--                                        r_jump <= s13;
--                                        r_stage <= s3;
--                                    else
--                                        --  we can go to sram programming
--                                        r_jump <= s21;
--                                        r_stage <= s3;
--                                    end if;
                                
--                                --  EEPROM PROGRAMMING : i just stay here and wait for the data to arrive
--                                --  when a specific code arrives, it signals that we have to terminate
--                                when s13 =>
--                                    r_jump <= s14;
--                                    msg_begin := 37;
--                                    msg_end := 73;
--                                    r_stage <= s0;
                                
--                                when s14 =>
--                                    bc := 0;
--                                    target_bc := 4;
--                                    r_jump <= s15;
--                                    r_stage <= s4;
                                
--                                when s15 =>
--                                    --  I have received 4 codes to put forward to the eeprom, so we apply the offset to the address
--                                    --  and proceed with the operation
--                                    if (sram_packet=x"ffffffff") then
--                                        --  termination of operation -> going to sram
--                                        r_jump <= s21;
--                                        r_stage <= s3;
--                                    else
--                                        addr := to_integer(unsigned(sram_packet(30 downto 8)));
--                                        r_dev_in_cmd <= '0';
--                                        r_dev_in_addr <= std_logic_vector(to_unsigned(i2c_eeprom_base + addr,23));
--                                        r_dev_in_data <= sram_packet(7 downto 0);
--                                        r_dev_in_keep <= '0';
--                                        --  going
--                                        r_stage <= s16;
--                                    end if;
                                
--                                when s16 =>
--                                    if (ss_dev_out_drdy='1') then
--                                        r_stage <= s17;
--                                    else
--                                        r_dev_in_latch <= '1';
--                                        r_stage <= s16;
--                                    end if;
                                
--                                when s17 =>
--                                    if (ss_dev_out_drdy='0') then
--                                        --  operation has been done on the eeprom,
--                                        --  i place now a small thing on the lcd
--                                        r_jump <= s13;
--                                        r_stage <= s18;
--                                    else
--                                        r_dev_in_latch <= '0';
--                                        r_stage <= s17;
--                                    end if;
                                
--                                --  PLACING A SINGLE DOT ON THE LCD TO SHOW PROGRESS
--                                when s18 =>
--                                    r_dev_in_cmd <= '0';
--                                    if (n=20) then
--                                        n := 0;
--                                        r_dev_in_addr <= std_logic_vector(to_unsigned(i2c_lcd_base + 8,23));
--                                        if (code=x"23") then
--                                            code := x"2e";
--                                        else
--                                            code := x"23";
--                                        end if;
--                                    else
--                                        n := n + 1;
--                                        r_dev_in_addr <= std_logic_vector(to_unsigned(i2c_lcd_base + 4,23));
--                                    end if;
--                                    r_dev_in_data <= code;
--                                    r_dev_in_keep <= '0';
--                                    r_stage <= s19;
                                
--                                when s19 =>
--                                    if (ss_dev_out_drdy='1') then
--                                        r_stage <= s20;
--                                    else
--                                        r_dev_in_latch <= '1';
--                                        r_stage <= s19;
--                                    end if;
                                
--                                when s20 =>
--                                    if (ss_dev_out_drdy='0') then
--                                        r_stage <= r_jump;
--                                    else
--                                        r_dev_in_latch <= '0';
--                                        r_stage <= s20;
--                                    end if;
                                                                
--                                --  SRAM PROGRAMMMING : I wait here for the data to arrive for the sram
--                                when s21 =>
--                                    r_jump <= s22;
--                                    msg_begin := 74;
--                                    msg_end := 110;
--                                    r_stage <= s0;
                                
--                                when s22 =>
--                                    --  now we need to wait for the choice
--                                    r_jump <= s23;
--                                    bc := 0;
--                                    target_bc := 1;
--                                    r_stage <= s4;
                                
--                                when s23 =>
--                                    if (sram_packet(7 downto 0)=x"49") then
--                                        --  we need to do sram programming
--                                        r_jump <= s24;
--                                        r_stage <= s3;
--                                    else
--                                        --  we can go to final stage
--                                        r_jump <= s29;
--                                        r_stage <= s3;
--                                    end if;
                                
--                                when s24 =>
--                                    r_jump <= s25;
--                                    msg_begin := 111;
--                                    msg_end := 147;
--                                    r_stage <= s0;
                                
--                                when s25 =>
--                                    bc := 0;
--                                    target_bc := 4;
--                                    r_jump <= s26;
--                                    r_stage <= s4;
                                
--                                when s26 =>
--                                    if (sram_packet=x"ffffffff") then
--                                        --  termination of operation -> going to final stage
--                                        r_jump <= s29;
--                                        r_stage <= s3;
--                                    else
--                                        r_dev_in_cmd <= '0';
--                                        r_dev_in_addr <= sram_packet(30 downto 8);
--                                        r_dev_in_data <= sram_packet(7 downto 0);
--                                        r_dev_in_keep <= '0';
--                                        --  going
--                                        r_stage <= s27;
--                                    end if;
                                
--                                when s27 =>
--                                    if (ss_dev_out_drdy='1') then
--                                        r_stage <= s28;
--                                    else
--                                        r_dev_in_latch <= '1';
--                                        r_stage <= s27;
--                                    end if;
                                
--                                when s28 =>
--                                    if (ss_dev_out_drdy='0') then
--                                        --  operation has been done on the eeprom,
--                                        --  i place now a small thing on the lcd
--                                        r_jump <= s25;
--                                        r_stage <= s18;
--                                    else
--                                        r_dev_in_latch <= '0';
--                                        r_stage <= s28;
--                                    end if;
                                
--                                --  FINAL STAGE
--                                when s29 =>
--                                    r_jump <= s30;
--                                    msg_begin := 148;
--                                    msg_end := 184;
--                                    r_stage <= s0;
                                
--                                when s30 =>
--                                    --  now everything is ready to start the processor...
--                                    --  I just need to sample the position of the up switch and when that switch is changed over, the processor will start.
--                                    --  if the switch is switched back, the processor will pause
--                                    --  the low switch is only enabled when the processor is paused. If that happens the processor is reset.
--                                    r_front_red <= '1';
--                                    r_stage <= s30;
                            end case;
                        end if;
                    end if;
                end process MAIN;
    
    --  driving signals
    cpuctrl_run <= r_cpuctrl_run;
    cpuctrl_reset <= r_cpuctrl_reset;
    --  front panel
    fp_green_led <= r_front_green;
    fp_red_led <= r_front_red;
    fp_leds <= r_fp_leds;
    --  uart
    uart_irq_grant_0 <= r_uart_irq_grant_0;
    
end Behavioral;

