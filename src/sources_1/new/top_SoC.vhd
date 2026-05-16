library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
--  changelog: 4/4/25
--  in bus_interface and dev source files I edited some ss double registering
--  in order to reduce the amount of logic levels and thus reduce the total negative slack in high fanout conditions.
entity top_SoC is
    generic (
        d0_mem_begin: integer := 164492;    --  cpu address start
        d0_mem_end: integer := 164692;      --  cpu address end: 164492 + 63 + 72 and the IRQ that uses from 164492+64+72 up until 164492+64+72+65
        d1_mem_begin: integer := 131136;    --  uart subsystem address start: 64 base/logical + 1 virtual for dev0 + 64 base/logical + 65 virtuals
        d1_mem_end: integer := 131329;      --  uart subsystem address end
        d2_mem_begin: integer := 0;         --  sram address start
        d2_mem_end: integer := 131135;      --  sram address end        
        d3_mem_begin: integer := 131330;    --  gpio address start
        d3_mem_end: integer := 131464;      --  gpio address end (2 virtual registers: portA data and portA data direction)
        d4_mem_begin: integer := 131465;    --  i2c address start
        d4_mem_end: integer := 164426;      --  i2c address end
        
        --  131465 + 64 : inizio della eeprom i2c a 131529
        --  a questo punto ho che 131529 e' lo zero della eeprom a cui devo sommare 32769 virtuals -> termina a 164297
        --  l'lcd inizia a 164298 e lo spazio virtuale suo inizia a 164362 e si estende per altri 64 registri virtuali
        
        d5_mem_begin: integer := 164427;    --  demo device
        d5_mem_end: integer := 164491;      --  demo device
        d6_mem_begin: integer := 164693;    --  EALU
        d6_mem_end: integer := 164757;      --  EALU
        d7_mem_begin: integer := 0;
        d7_mem_end: integer := 0
    ); 
    port (
        sysClk:         in      std_logic;
        sysRstb:        in      std_logic;
        --  serial lines
        serial_input:   in      std_logic;
        serial_output:  out     std_logic;
        --  i2c lines
        i2c_scl:        out     std_logic;
        i2c_sda:        inout   std_logic;
        --  vga lines
        vga_R:          out     std_logic_vector(3 downto 0);
        vga_G:          out     std_logic_vector(3 downto 0);
        vga_B:          out     std_logic_vector(3 downto 0);
        vga_HS:         out     std_logic;
        vga_VS:         out     std_logic;
        --  GPIO interface - PORT A is connected to the keyboard
        portA:          inout   std_logic_vector(7 downto 0);
        drdyA:          in      std_logic;
        dackA:          out     std_logic;
        --  PORT B is general purpose
        portB:          inout   std_logic_vector(7 downto 0);
        drdyB:          in      std_logic;
        dackB:          out     std_logic;
        --  SRAM
        DATA:           inout   std_logic_vector(7 downto 0);
        SRAM_TRXDIR:    out     std_logic;
        SRAM_TRXOE:     out     std_logic;
        RAL_L:          out     std_logic;
        RAL_H:          out     std_logic;
        SRAM_WE:        out     std_logic;
        SRAM_OE:        out     std_logic;
        SRAM_CE:        out     std_logic;
        SRAM_LH:        out     std_logic;
        --  debug signals
        leds:           out     std_logic_vector(7 downto 0);
        sw :            in      std_logic_vector(3 downto 0);
        btn0:           in      std_logic;
        dbg_S:          out     std_logic;
        dbg_M:          out     std_logic
    );
end top_SoC;

architecture Behavioral of top_SoC is
    --  bus arbiter lines
    signal rq_lines: std_logic_vector(7 downto 0) := (others=>'0');
    signal grant_lines: std_logic_vector(7 downto 0);
    signal bus_busy: std_logic;
    
    --  system bus
    signal strobe_M: std_logic;
    signal strobe_S: std_logic;
    signal keep: std_logic;
    signal bus_lines: std_logic_vector(31 downto 0);
    
    --  device 0 control
    signal r_dev_in_cmd_0: std_logic := '0';
    signal r_dev_in_addr_0: std_logic_vector(22 downto 0) := (others=>'0');
    signal r_dev_in_data_0: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_dev_in_keep_0: std_logic := '0';
    signal r_dev_in_latch_0: std_logic := '0';
    
    signal s_dev_out_cmd_0: std_logic;
    signal s_dev_out_addr_0: std_logic_vector(22 downto 0);
    signal s_dev_out_data_0: std_logic_vector(7 downto 0);
    signal s_dev_out_drdy_0: std_logic;
    signal s_dev_out_done_0: std_logic;
    signal s_dev_err_0: std_logic;
    signal s_dev_chg_0: std_logic;
    
    signal ss_dev_out_cmd_0: std_logic := '0';
    signal ss_dev_out_addr_0: std_logic_vector(22 downto 0) := (others=>'0');
    signal ss_dev_out_data_0: std_logic_vector(7 downto 0) := (others=>'0');
    signal ss_dev_out_drdy_0: std_logic := '0';
    signal ss_dev_out_done_0: std_logic := '0';
    signal ss_dev_err_0: std_logic := '0';
    signal ss_dev_chg_0: std_logic := '0';
    
    --  activation signal
    signal ss_sw0: std_logic := '0';
    
    signal dbg_stage: natural;
    signal dbg_hw: natural;
    signal dbg_trx: natural;
    
    signal dbg_bridge_main: natural;
    signal dbg_bridge_ext: natural;
    signal dbg_bridge_int:  natural;
    
    --  small rom to hold in some characters
    type ROM_ARRAY is array (0 to 89 ) of std_logic_vector (7 downto 0);
    signal uart_data: ROM_ARRAY := (x"48",x"65",x"6c",x"6c",x"6f",x"2c",x"0a",x"57",x"6f",
                                    x"72",x"6c",x"64",x"21",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
                                    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00"
                                    ); 
    
    type PGM_ARRAY is array (0 to 29) of std_logic_vector (7 downto 0);
    signal pgm_asm: PGM_ARRAY := (
                                    x"41",x"00",x"00",  --  opA
                                    x"cd",x"82",x"02",  --  opB
                                    x"0a",x"80",x"00",  --  opC
                                    x"04",    --  instruction 0 : !0x41 tmp1 +1
                                    x"cd",x"82",x"02",  --  opA
                                    x"80",x"00",x"02",  --  opB
                                    x"14",x"80",x"00",  --  opC
                                    x"05",    --  instruction 1 : tmp1 uart +1
                                    x"ff",x"00",x"00",  --  opA
                                    x"cf",x"82",x"02",  --  opB
                                    x"14",x"80",x"00",  --  opC
                                    x"04"     --  instruction 2 : !0xff fs 0
                                );
      
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s0, s1, s2, s3, s4, s5, s6, s7, s8, s8a, s8b, s8c, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM;
    signal buff: ROM_ARRAY;
    
    signal leds_0: std_logic_vector(7 downto 0);
    signal leds_1: std_logic_vector(7 downto 0);
    
    --  irq lines
    signal irq_lines: std_logic_vector(7 downto 0);
    signal irq_grant: std_logic_vector(7 downto 0);
    
    
    type ram_type is array (0 to 4) of std_logic_vector(7 downto 0);
    signal reg_file: ram_type;

    signal isr_packet: std_logic_vector(31 downto 0);    
    signal sram_packet: std_logic_vector(31 downto 0);
    
    signal dbg_sdev_0: natural;
    signal dbg_sdev_1: natural;
    signal dbg_bridge_0: natural;
    
    signal run_cpu: std_logic := '0';
    signal pause_cpu: std_logic := '1';
    
    signal dbg_instr: natural;
    signal dbg_irq: natural;
    signal cpu_output: std_logic_vector(31 downto 0);
    signal sdv_output: std_logic_vector(31 downto 0);
    
    signal uart_irq_0: std_logic := '0';
    signal uart_irq_grant_0: std_logic;
    
    signal dbg_bridge_1: natural;
    
    signal s_dbg_dev0_main: natural;
    signal s_dbg_dev0_int: natural;
    
    signal dbg_sdev_0_subbus: natural;
    signal dbg_sdev_0_subbus_dev: natural;
    
    signal boh: std_logic_vector(31 downto 0);

begin    
    --  line terminations
    irq_lines(7 downto 1) <= (others=>'0');    
    
    --  bus arbiter
    BUS_ARB:    entity work.bus_arb(Behavioral)
                generic map (
                    n_rq_lines => 8
                ) port map (
                    sysClk => sysClk,
                    sysRstb => '1',
                    --  request lines
                    rq_lines => rq_lines,
                    grant_lines => grant_lines,
                    busy => bus_busy
                );
    
    --  uart device
    DEV_UART:   entity work.dev_UART_v2(Behavioral)
                generic map (
                    dev_id => 1,
                    dev_mem_begin => d1_mem_begin,  --  base+logici da 131136 a 131199
                    dev_mem_end => d1_mem_end,      --  virtuale 0 e0 il 131200
                    cpu_irq_addr_0 => d5_mem_begin+64,  --  le richieste di interrupt del dev0 sono indirizzate qui
                    cpu_irq_addr_1 => d0_mem_begin+200  --  le richieste di interrupt del dev1 sono invece indirizzate alla cpu direttamente sull'IRH
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_rq => rq_lines(1),
                    bus_grant => grant_lines(1),
                    bus_busy => bus_busy,
                    --  interrupt lines 2 and 1 are assigned to the uart
                    irq_line_0 => uart_irq_0, --irq_lines(2 downto 1),
                    irq_grant_0 => uart_irq_grant_0, --irq_grant(2 downto 1),
                    irq_line_1 => irq_lines(0),
                    irq_grant_1 => irq_grant(0),
                    --  hardware lines
                    serial_input => serial_input,
                    serial_output => serial_output,
                    --  debug
                    dbg_sdev_0_main => dbg_sdev_0,
                    dbg_sdev_0_subbus => dbg_sdev_0_subbus,
                    dbg_sdev_0_subbus_dev => dbg_sdev_0_subbus_dev,
                    dbg_sdev_1 => dbg_sdev_1,
                    --  bridge debug
                    dbg_bridge => dbg_bridge_main,
                    dbg_bridge_ext => dbg_bridge_ext,
                    dbg_bridge_int => dbg_bridge_int
                );
               
                
    
    --  sram device
    DEV_SRAM:   entity work.dev_SRAM_v2(Behavioral)
                generic map (
                    dev_id => 2,
                    dev_mem_begin => d2_mem_begin,  --  base + logici da 0 a 63
                    dev_mem_end => d2_mem_end       --  virtuali tra 64 e 131135
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_rq => rq_lines(2),
                    bus_grant => grant_lines(2),
                    bus_busy => bus_busy,
                    --  hardware lines
                    DATA => DATA,
                    SRAM_TRXDIR => SRAM_TRXDIR,
                    SRAM_TRXOE => SRAM_TRXOE,
                    SRAM_CE => SRAM_CE,
                    SRAM_OE => SRAM_OE,
                    SRAM_WE => SRAM_WE,
                    SRAM_LH => SRAM_LH,
                    RAL_L => RAL_L,
                    RAL_H => RAL_H
                );
    
    --  GPIO device
    DEV_GPIO:   entity work.dev_GPIO_v2(Behavioral)
                generic map (
                    dev_id => 3,
                    dev_mem_begin => d3_mem_begin,
                    dev_mem_end => d3_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_rq => rq_lines(3),
                    bus_grant => grant_lines(3),
                    bus_busy => bus_busy,
                    --  hardware lines
                    portA => portA,
                    drdyA => drdyA,
                    dackA => dackA,
                    portB => portB,
                    drdyB => drdyB,
                    dackB => dackB--,
                    --  debug
                    --dbg_0 => leds_0,
                    --dbg_1 => leds_1,
                    --dbg_S => dbg_S,
                    --dbg_M => dbg_M
                );
    
    --  I2C device
    DEV_I2C:    entity work.dev_I2C_v2(Behavioral)
                generic map (
                    dev_id => 4,
                    dev_mem_begin => d4_mem_begin,
                    dev_mem_end => d4_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_rq => rq_lines(4),
                    bus_grant => grant_lines(4),
                    bus_busy => bus_busy,
                    --  hardware lines
                    i2c_scl => i2c_scl,
                    i2c_sda => i2c_sda,
                    --  debug
                    dbg_stage => dbg_stage,
                    dbg_hw => dbg_hw,
                    dbg_trx => dbg_trx
                );
    
    --  CPU device
    DEV_CPU:    entity work.dev_CPU_v2(Behavioral)
                generic map (
                    dev_id => 0,
                    dev_mem_begin => d0_mem_begin,
                    dev_mem_end => d0_mem_end,
                    reset_vector => 32768
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_rq => rq_lines(0),
                    bus_grant => grant_lines(0),
                    bus_busy => bus_busy,
                    --  cpu controls
                    run => run_cpu,
                    pause => pause_cpu,
                    --  hardware lines
                    irq_lines => irq_lines,
                    irq_grant => irq_grant,
                    --  debug
                    dbg_instr => dbg_instr,
                    dbg_irq => dbg_irq
                );
    
    --  EALU device
    DEV_EALU:   entity work.dev_EALU_v2(Behavioral)
                generic map (
                    dev_id => 6,
                    dev_mem_begin => d6_mem_begin,
                    dev_mem_end => d6_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_rq => rq_lines(6),
                    bus_grant => grant_lines(6),
                    bus_busy => bus_busy
                );
                
    --  demo device to interface here
    DEV_DEMO:   entity work.dev_v2(Behavioral)
                generic map (
                    dev_id => 5,
                    dev_mem_begin => d5_mem_begin,
                    dev_mem_end => d5_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_rq => rq_lines(5),
                    bus_grant => grant_lines(5),
                    bus_busy => bus_busy,
                    --  external interface signals
                    dev_in_cmd => r_dev_in_cmd_0,
                    dev_in_addr => r_dev_in_addr_0,
                    dev_in_data => r_dev_in_data_0,
                    dev_in_keep => r_dev_in_keep_0,
                    dev_in_latch => r_dev_in_latch_0,
                    dev_out_cmd => s_dev_out_cmd_0,
                    dev_out_addr => s_dev_out_addr_0,
                    dev_out_data => s_dev_out_data_0,
                    dev_out_drdy => s_dev_out_drdy_0,
                    dev_out_done => s_dev_out_done_0,
                    dev_err => s_dev_err_0,
                    dev_chg => s_dev_chg_0,
                    --  debug
                    dbg_stage => s_dbg_dev0_main,
                    devbus_interface => s_dbg_dev0_int
                );
                
                
    
    MAIN:       process(sysClk)
                    variable c: natural := 0;
                    variable f: std_logic_vector(1 downto 0) := "00";
                    variable bc: natural := 0;
                    variable data: std_logic_vector(7 downto 0) := (others=>'0');
                    variable addr: natural := 0;
                    variable b_addr: std_logic_vector(22 downto 0) := (others=>'0');
                    variable tt: std_logic_vector(7 downto 0) := (others=>'0');
                    variable tot_bytes: natural := 0;
                    variable full_c: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                uart_irq_grant_0 <= '0';
                                r_stage <= s_IDLE;
                            
                            when s_IDLE =>
                                run_cpu <= '0';
                                leds_0 <= std_logic_vector(to_unsigned(0,8));
                                --  adesso facciamo una prova, in cui comunichiamo con la gpio e vediamo se ha delle cose per noi
                                case (sw(1 downto 0)) is
                                    when "00" =>
                                        r_stage <= s_IDLE;
                                   
                                    when "01" =>
                                        c := 0;
                                        bc := 0;
                                        r_stage <= s0;
                                    
                                    when "10" =>
                                        c := 0;
                                        bc := 0;
                                        r_stage <= s4;
                                    
                                    when "11" =>
                                        r_stage <= s_IDLE; 
                                end case;
                            
                            when s0 =>
                                leds_0 <= std_logic_vector(to_unsigned(1,8));
                                --  imposto indirizzo
                                r_dev_in_cmd_0 <= '0';
                                r_dev_in_addr_0 <= std_logic_vector(to_unsigned(d4_mem_begin+64+32768+1+64+4, 23));
                                r_dev_in_data_0 <= uart_data(bc);
                                if (bc=13) then
                                    r_dev_in_keep_0 <= '0';
                                else
                                    r_dev_in_keep_0 <= '1';
                                end if;
                                r_stage <= s1; 
                            
                            when s1 =>
                                leds_0 <= std_logic_vector(to_unsigned(2,8));
                                if (s_dev_out_done_0='1') then
                                    bc := bc + 1;
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s2;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s1;
                                end if;
                            
                            when s2 =>
                                leds_0 <= std_logic_vector(to_unsigned(3,8));
                                if (s_dev_out_done_0='0') then
                                    if (bc=13) then
                                        r_stage <= s3;
                                    else
                                        r_stage <= s0;
                                    end if;
                                 else
                                    r_stage <= s2;
                                 end if;    
                            
                            when s3 =>
                                leds_0 <= std_logic_vector(to_unsigned(4,8));
                                if (sw(0)='0') then
                                    c := 0;
                                    bc := 0;
                                    r_stage <= s_IDLE;
                                else
                                    r_stage <= s3;
                                end if;
                            
                            --  now we wait for the UART to send in the data to store into the SRAM
                            --  the uart dev already handles the transaction and it gives us interrupts
                            --  basically it sends us an IRQ request with the data we have to read.
                            when s4 =>
                                --  waiting for an interrupt by the uart or for the manual start signal for the cpu
                                leds_0 <= std_logic_vector(to_unsigned(5, 8));
                                case (sw(1 downto 0)) is
                                    when "00" =>
                                        --  cpu has to be run
                                        c := 0;
                                        r_stage <= s17;
                                    
                                    when "10" =>
                                        --  program mode
                                        if (uart_irq_0='1') then
                                            --  the uart is sending an interrupt
                                            --  an interrupt request is comprised of 4 bytes
                                            --  lower byte: 4 to 0 -> interrupt routine pointer
                                            --  rest of the bytes: 27 downto 5 => address from which we have to read, let's see
                                            c := 0;
                                            uart_irq_grant_0 <= '1';
                                            r_stage <= s5;
                                        else
                                            uart_irq_grant_0 <= '0';
                                            r_stage <= s4;
                                        end if;
                                    
                                    when others =>
                                        r_stage <= s4;
                                end case;
                            
                            when s5 =>
                                --  now that grant is high, the uart will send the 4 bytes, so
                                leds_0 <= std_logic_vector(to_unsigned(6, 8));
                                if (s_dev_out_drdy_0='1') then
                                    --  data is here
                                    isr_packet(((c+1)*8)-1 downto (c*8)) <= s_dev_out_data_0;
                                    r_stage <= s6;
                                else
                                    --  waiting for the ISR data
                                    r_stage <= s5;
                                end if;
                            
                            when s6 =>
                                leds_0 <= std_logic_vector(to_unsigned(7, 8));
                                if (s_dev_out_drdy_0='0') then
                                    r_dev_in_latch_0 <= '0';
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
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s6;
                                end if;
                            
                            when s7 =>
                                leds_0 <= std_logic_vector(to_unsigned(8, 8));
                                if (uart_irq_0='0') then
                                    --  it has lowered it, so we can now read the interrupt byte from it
                                    r_dev_in_cmd_0 <= '1';
                                    r_dev_in_addr_0 <= isr_packet(27 downto 5);
                                    r_dev_in_data_0 <= (others=>'0');
                                    r_dev_in_keep_0 <= '0';
                                    r_stage <= s8;
                                else
                                    --  waiting for the device to lower its irq line
                                    r_stage <= s7;
                                end if;
                            
                            when s8 =>
                                --  now I need to perform the read
                                leds_0 <= std_logic_vector(to_unsigned(9, 8));
                                if (s_dev_out_drdy_0='1') then
                                    --  device has responded with the data I need, so:
                                    sram_packet(((bc+1)*8)-1 downto (bc*8)) <= s_dev_out_data_0;
                                    r_stage <= s9;
                                else
                                    --  waiting
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s8;
                                end if;
                            
                            when s9 =>
                                --  disengaging
                                leds_0 <= std_logic_vector(to_unsigned(10, 8));
                                if (s_dev_out_drdy_0='0') then
                                    --  check how many so that we can write to the SRAM
                                    if (bc=3) then
                                        --  gathered everything -> we can write
                                        bc := 0;
                                        r_stage <= s10;
                                    else
                                        --  still need to gather before going to the SRAM
                                        uart_irq_grant_0 <= '0';
                                        bc := bc + 1;                                    
                                        r_stage <= s4;
                                    end if;
                                else
                                    --  waiting
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s9;
                                end if;
                            
                            when s10 =>
                                --  writing to SRAM
                                leds_0 <= std_logic_vector(to_unsigned(11, 8));
                                r_dev_in_cmd_0 <= '0';
                                r_dev_in_data_0 <= sram_packet(7 downto 0);
                                r_dev_in_addr_0 <= sram_packet(30 downto 8);
                                r_dev_in_keep_0 <= '0';
                                r_stage <= s11;
                            
                            when s11 =>
                                --  latching
                                leds_0 <= std_logic_vector(to_unsigned(12, 8));
                                if (s_dev_out_drdy_0='1') then
                                    --  written to sram
                                    r_stage <= s12;
                                else
                                    --  latching data
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s11;
                                end if;
                            
                            when s12 =>
                                leds_0 <= std_logic_vector(to_unsigned(13, 8));
                                if (s_dev_out_drdy_0='0') then
                                    --  now we can go and read what we've just written and send it back to the uart as confirmation?
                                    r_dev_in_cmd_0 <= '1';
                                    r_stage <= s13;
                                else
                                    --  latched everything
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s12;
                                end if;
                            
                            when s13 =>
                                leds_0 <= std_logic_vector(to_unsigned(14, 8));
                                if (s_dev_out_drdy_0='1') then
                                    r_dev_in_data_0 <= s_dev_out_data_0;
                                    r_stage <= s14;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s13;
                                end if;
                            
                            when s14 =>
                                leds_0 <= std_logic_vector(to_unsigned(15, 8));
                                if (s_dev_out_drdy_0='0') then
                                    r_dev_in_cmd_0 <= '0';
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(d1_mem_begin+64, 23));
                                    r_stage <= s15;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s14;
                                end if;
                            
                            when s15 =>
                                leds_0 <= std_logic_vector(to_unsigned(16, 8));
                                if (s_dev_out_drdy_0='1') then
                                    r_stage <= s16;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s15;
                                end if;
                            
                            when s16 =>
                                leds_0 <= std_logic_vector(to_unsigned(17, 8));
                                if (s_dev_out_drdy_0='0') then
                                    uart_irq_grant_0 <= '0';
                                    r_stage <= s4;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s16;
                                end if;
                                                                                    
                            when s17 =>
                                leds_0 <= std_logic_vector(to_unsigned(18, 8));
                                case (sw(1 downto 0)) is
                                    when "00" =>
                                        --  cpu is running
                                        run_cpu <= '1';
                                        pause_cpu <= '0';
                                        r_stage <= s17;
                                    
                                    when "10" =>
                                        --  halt
                                        run_cpu <= '0';
                                        pause_cpu <= '0';
                                        r_stage <= s4;
                                    
                                    when others =>
                                        r_stage <= s17;
                                end case;
                            
                            when others =>
                                r_stage <= s_IDLE;
                        end case;
                    end if;
                end process MAIN;
                            
    --  assignments for vga
    vga_R <= (others=>'0');
    vga_G <= (others=>'0');
    vga_B <= (others=>'0');
    vga_HS <= '1';
    vga_VS <= '1';
    
    --  debug lines
    dbg_S <= '0';
    dbg_M <= '0';
    
--  debug
    VIS:    process(sysClk)
            begin
                if (falling_edge(sysClk)) then
                    cpu_output <= std_logic_vector(to_unsigned(dbg_instr, 32));
                    sdv_output <= std_logic_vector(to_unsigned(dbg_irq, 32));
                end if;
            end process VIS;
    
    with (sw) select
        leds <= cpu_output(7 downto 0) when "0000",
                sdv_output(7 downto 0) when "0100",
                leds_0 when others;
        
end Behavioral;
