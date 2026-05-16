library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
--  changelog: 4/4/25
--  in bus_interface and dev source files I edited some ss double registering
--  in order to reduce the amount of logic levels and thus reduce the total negative slack in high fanout conditions.
entity top_final_debug is
    generic (
        d0_mem_begin: integer := 164492;    --  cpu address start
        d0_mem_end: integer := 164694;      --  cpu address end: 164492 + 63 + 74 and the IRQ that uses from 164492+64+74 up until 164492+64+74+65
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
        d6_mem_begin: integer := 164695;    --  unused device
        d6_mem_end: integer := 164759;      --  unused device
        --  the VGA card has two modes (transparents): text or graphic mode. When used in text mode, we have 40x30 = 1200 characters on screen
        --  so we need 1200 virtual registers to manipulate these directly. When used in graphic mode, each individual pixel is addressable, and
        --  so we have 320x240 = 76800 virtual registers. In total, we thus have: 78000 virtual registers to specify.
        --  starting from 164760 we arrive up to 
        d7_mem_begin: integer := 164760;    --  VGA: the first 64 (0 to 63) are the physical, all the others are virtual
        d7_mem_end: integer := 289407       --  physical: 164760 to 164760+63 = 164823
                                            --  virtual locations: 164824 to 164824+124583 = 289407
                                            --  I could also add more for specific command functions of the "video card", so
                                            
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
        --  front panel
        front_leds:     out     std_logic_vector(7 downto 0);
        front_green:    out     std_logic;
        front_red:      out     std_logic;
        front_switch:   in      std_logic_vector(1 downto 0);
        --  debug signals
        leds:           out     std_logic_vector(7 downto 0);
        sw :            in      std_logic_vector(3 downto 0)        
    );
end top_final_debug;

architecture Behavioral of top_final_debug is
    --  bus arbiter lines
    signal rq_lines: std_logic_vector(7 downto 0) := (others=>'0');
    signal grant_lines: std_logic_vector(7 downto 0);
    signal bus_busy: std_logic;
    
    --  system bus
    signal strobe_M: std_logic;
    signal strobe_S: std_logic;
    signal keep: std_logic;
    signal bus_lines: std_logic_vector(31 downto 0);
    signal bus_done_S: std_logic;
    
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
    
    signal ss_uart_irq_0: std_logic := '0';
    
    --  activation signal
    signal ss_sw0: std_logic := '0';
    
    signal dbg_stage: natural;
    signal dbg_hw: natural;
    signal dbg_trx: natural;
    
    signal dbg_bridge_main: natural;
    signal dbg_bridge_ext: natural;
    signal dbg_bridge_int:  natural;
          
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s0, s1, s2, s3, s3b, s3c, s3d, s3e, s3f, s3g, s3h, s3i, s3l, s3j, s3k,
    s4, s5, s6, s6a, s7, s8, s8a, s8b, s8c, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM;
    
    
    signal leds_0: std_logic_vector(7 downto 0);
    signal leds_1: std_logic_vector(7 downto 0);
    
    --  irq lines
    signal irq_lines: std_logic_vector(7 downto 0);
    signal irq_grant: std_logic_vector(7 downto 0);

    signal isr_packet: std_logic_vector(31 downto 0);    
    signal sram_packet: std_logic_vector(31 downto 0);
    
    signal dbg_sdev_0: natural;
    signal dbg_sdev_1: natural;
    signal dbg_bridge_0: natural;
    
    
    
    signal dbg_instr: natural;
    signal dbg_irq: natural;
    
    signal uart_irq_0: std_logic := '0';
    signal uart_irq_grant_0: std_logic;
    
    signal dbg_bridge_1: natural;
    
    signal s_dbg_dev0_main: natural;
    signal s_dbg_dev0_int: natural;
    
    signal dbg_sdev_0_subbus: natural;
    signal dbg_sdev_0_subbus_dev: natural;
    
    
    signal dbg_sdev_1_subbus: natural;
    signal dbg_sdev_1_subbus_dev: natural;
    
    
    signal s_dbg_dev2_main: natural;
    signal s_dbg_dev2_int: natural;
    
    signal boh: std_logic_vector(31 downto 0);
    signal boh2: std_logic_vector(31 downto 0);
    signal boh3: std_logic_vector(31 downto 0);

    signal run_cpu: std_logic := '0';
    signal reset_cpu: std_logic := '0';
    signal halt_cpu: std_logic;
    
    signal dbg_cpu_subbus_dev: natural;
    signal dbg_cpu_subbus_dev_int: natural;
    signal cpu_output_port: natural;
    signal cpu_irq_isr: natural; 
    signal dbg_i2c_eeprom: natural;
    
    --  synchronizer
    signal ss_sync_0: std_logic := '0';
    
    --  display init
    type t_Memory is array (0 to 79) of std_logic_vector(7 downto 0);
    signal r_Mem : t_Memory := (--  first screen
                                x"52",x"4f",x"4d",x"2f",x"53",x"52",x"41",x"4d",x"20",x"50",x"52",x"4f",x"47",x"52",x"41",x"4d",x"4d",x"49",x"4e",x"47",
                                x"00",x"57",x"61",x"69",x"74",x"69",x"6e",x"67",x"20",x"66",x"6f",x"72",x"20",x"64",x"61",x"74",x"61",x"2e",x"2e",x"2e",
                                x"00",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",
                                x"20",x"00",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20",x"20"
                                );
        
begin    
    --  line terminations
    irq_lines(7 downto 1) <= (others=>'0');
    --rq_lines(7) <= '0';
    
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
                    cpu_irq_addr_1 => d0_mem_begin+202  --  le richieste di interrupt del dev1 sono invece indirizzate alla cpu direttamente sull'IRH (era 200, ora 202 perche' ho aggiunto 2 registri)
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_done_S => bus_done_S,
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
                    --  debug sdev 0
                    dbg_sdev_0_main => dbg_sdev_0,
                    dbg_sdev_0_subbus => dbg_sdev_0_subbus,
                    dbg_sdev_0_subbus_dev => dbg_sdev_0_subbus_dev,
                    --  debug sdev 1
                    dbg_sdev_1_main => dbg_sdev_1,
                    dbg_sdev_1_subbus => dbg_sdev_1_subbus,
                    dbg_sdev_1_subbus_dev => dbg_sdev_1_subbus_dev,
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
                    bus_done_S => bus_done_S,
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
                    RAL_H => RAL_H,
                    --  debug
                    dbg_dev => s_dbg_dev2_main,
                    dbg_dev_int => s_dbg_dev2_int
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
                    bus_done_S => bus_done_S,
                    bus_rq => rq_lines(3),
                    bus_grant => grant_lines(3),
                    bus_busy => bus_busy,
                    --  hardware lines
                    portA => portA,
                    drdyA => drdyA,
                    dackA => dackA,
                    portB => portB,
                    drdyB => drdyB,
                    dackB => dackB
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
                    bus_done_S => bus_done_S,
                    bus_rq => rq_lines(4),
                    bus_grant => grant_lines(4),
                    bus_busy => bus_busy,
                    --  hardware lines
                    i2c_scl => i2c_scl,
                    i2c_sda => i2c_sda,
                    --  debug
                    dbg_stage => dbg_stage,
                    dbg_hw => dbg_hw,
                    dbg_trx => dbg_trx,
                    dbg_stage_0 => dbg_i2c_eeprom
                );

    --  CPU device
    --  NOTE: the resect vector is shifted forward by 64 to avoid the sram's internal registers
    DEV_CPU:    entity work.dev_CPU_v2(Behavioral)
                generic map (
                    dev_id => 0,
                    dev_mem_begin => d0_mem_begin,
                    dev_mem_end => d0_mem_end,
                    reset_vector => 32768 + 64
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_done_S => bus_done_S,
                    bus_rq => rq_lines(0),
                    bus_grant => grant_lines(0),
                    bus_busy => bus_busy,
                    --  cpu controls
                    run => run_cpu,
                    reset => reset_cpu,
                    halt => halt_cpu,
                    --  hardware lines
                    irq_lines => irq_lines,
                    irq_grant => irq_grant,
                    --  debug
                    dbg_instr => dbg_instr,
                    cpu_output_port => cpu_output_port,
                    dbg_irq => dbg_irq,
                    dbg_cpu_subbus_dev => dbg_cpu_subbus_dev,
                    dbg_cpu_subbus_dev_int => dbg_cpu_subbus_dev_int,
                    dbg_irq_isr => cpu_irq_isr
                );

    --  bus termination
    rq_lines(6) <= '0';
    
    --  VGA device
    DEV_VGA:    entity work.dev_VGA_v2(Behavioral)
                generic map (
                    dev_id => 7,
                    dev_mem_begin => d7_mem_begin,
                    dev_mem_end => d7_mem_end
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus
                    bus_lines => bus_lines,
                    bus_strobe_M => strobe_M,
                    bus_strobe_S => strobe_S,
                    bus_keep => keep,
                    bus_done_S => bus_done_S,
                    bus_rq => rq_lines(7),
                    bus_grant => grant_lines(7),
                    bus_busy => bus_busy,
                    --  hardware lines
                    vga_R => vga_R,
                    vga_G => vga_G,
                    vga_B => vga_B,
                    vga_HS => vga_HS,
                    vga_VS => vga_VS
                );
    
    --  SUPER device (substitutes the 'DEMO' written here)
--    DEV_SUPER:  entity work.dev_SUPER(Behavioral)
--                generic map (
--                    dev_id => 5,
--                    dev_mem_begin => d5_mem_begin,
--                    dev_mem_end => d5_mem_end
--                ) port map (
--                    sysClk => sysClk,
--                    sysRstb => sysRstb,
--                    --  system bus
--                    bus_lines => bus_lines,
--                    bus_strobe_M => strobe_M,
--                    bus_strobe_S => strobe_S,
--                    bus_keep => keep,
--                    bus_done_S => bus_done_S,
--                    bus_rq => rq_lines(5),
--                    bus_grant => grant_lines(5),
--                    bus_busy => bus_busy,
--                    --  hardware lines
--                    cpuctrl_run => run_cpu,
--                    cpuctrl_reset => reset_cpu,
--                    cpuctrl_halt => halt_cpu,
--                    cpu_output_port => cpu_output_port,
--                    --  front panel
--                    fp_green_led => front_green,
--                    fp_red_led => front_red,
--                    fp_switches => front_switch,
--                    fp_leds => front_leds,
--                    --  uart 0
--                    uart_irq_0 => uart_irq_0,
--                    uart_irq_grant_0 => uart_irq_grant_0
--                );
    
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
                    bus_done_S => bus_done_S,
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
    
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_dev_out_drdy_0 <= '0';
                                ss_dev_out_data_0 <= (others=>'0');
                                ss_uart_irq_0 <= '0';
                                ss_sync_0 <= '0';                            
                            
                            when s3 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s3b =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s3d =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s3e =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s3g =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s3h =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                                                                                    
                            when s4 =>
                                ss_uart_irq_0 <= uart_irq_0;
                            
                            when s5 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                                ss_dev_out_data_0 <= s_dev_out_data_0;
                            
                            when s6 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                                                                                    
                            when s7 =>
                                ss_uart_irq_0 <= uart_irq_0;
                                ss_sync_0 <= '1';
                            
                            when s8 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                                ss_dev_out_data_0 <= s_dev_out_data_0;
                                ss_sync_0 <= '0';
                            
                            when s9 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s11 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s12 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s13 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                                ss_dev_out_data_0 <= s_dev_out_data_0;
                            
                            when s14 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s15 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s16 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                            
                            when s18 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                                
                            when s19 =>
                                ss_dev_out_drdy_0 <= s_dev_out_drdy_0;
                                
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
    
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
                    variable first: std_logic := '1';
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                uart_irq_grant_0 <= '0';
                                tt := x"23";
                                r_jump <= s3f;
                                r_stage <= s_IDLE;
                            
                            when s_IDLE =>
                                run_cpu <= '0';
                                if (sw(0)='1') then
                                    r_stage <= s1;
                                else
                                    r_stage <= s_IDLE;
                                end if;
                            
                            when s0 =>
                                --  cpu is now running
                                leds_0 <= x"b0";
                                run_cpu <= '1';
                                r_stage <= s0;
                                                        
                            when s1 =>
                                --  displaying the initialization
                                leds_0 <= std_logic_vector(to_unsigned(1, 8));
                                case (sw(1 downto 0)) is
                                    when "01" =>
                                        c := 0;
                                        r_stage <= s2;
                                    
                                    when others =>
                                        r_stage <= s1;
                                end case;
                            
                            when s2 =>
                                leds_0 <= std_logic_vector(to_unsigned(2, 8));
                                r_dev_in_cmd_0 <= '0';
                                if (r_Mem(c)=x"00") then
                                    --  bisogna andare a capo
                                    r_dev_in_data_0 <= x"01";
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(164362 + 7,23));
                                else
                                    r_dev_in_data_0 <= r_Mem(c);
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(164362 + 4,23));
                                end if;
                                if (c=79) then
                                    r_dev_in_keep_0 <= '0';
                                else
                                    r_dev_in_keep_0 <= '1';
                                end if;
                                r_stage <= s3;
                            
                            when s3 =>
                                leds_0 <= std_logic_vector(to_unsigned(3, 8));
                                if (ss_dev_out_drdy_0='1') then
                                    r_stage <= s3b;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s3;
                                end if;
                            
                            when s3b =>
                                leds_0 <= std_logic_vector(to_unsigned(4, 8));
                                if (ss_dev_out_drdy_0='0') then
                                    if (c=79) then
                                        c := 0;
                                        full_c := 0;
                                        r_stage <= s3c;
                                    else
                                        c := c + 1;
                                        r_stage <= s2;
                                    end if;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s3b;
                                end if;
                            
                            when s3c =>
                                --  adesso il comando per posizionare il cursore:
                                r_dev_in_data_0 <= "01000000";
                                r_dev_in_cmd_0 <= '0';
                                r_dev_in_addr_0 <= std_logic_vector(to_unsigned(164362 + 5,23));
                                r_dev_in_keep_0 <= '0';
                                r_stage <= s3d;
                            
                            when s3d =>
                                if (ss_dev_out_drdy_0='1') then
                                    r_stage <= s3e;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s3d;
                                end if;
                            
                            when s3e =>
                                if (ss_dev_out_drdy_0='0') then
                                    r_stage <= r_jump;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s3e;
                                end if;
                            
                            when s3f =>
                                --  ora con la VGA provo a far muovere un codice per lo schermo in un loop infinito, vediamo
                                --  qui si scrive in orizzontale
                                r_dev_in_cmd_0 <= '0';
                                r_dev_in_data_0 <= x"40";
                                if (full_c=0) then
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(164760 + 64 + 8, 23));
                                    r_dev_in_keep_0 <= '1';
                                else
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(164760 + 64 + 11, 23));
                                    if (c=19) then
                                        r_dev_in_keep_0 <= '0';
                                    else
                                        r_dev_in_keep_0 <= '1';
                                    end if;                                        
                                end if;
                                r_stage <= s3g;
                                                        
                            when s3g =>
                                if (ss_dev_out_drdy_0='1') then
                                    r_stage <= s3h;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s3g;
                                end if;
                            
                            when s3h =>
                                if (ss_dev_out_drdy_0='0') then
                                    if (full_c=0) then
                                        if (c=29) then
                                            c := 0;
                                            full_c := 1;
                                            r_stage <= s3f;
                                        else
                                            bc := 0;
                                            c := c + 1;
                                            r_stage <= s3i;
                                        end if;
                                    else
                                        if (c=19) then
                                            c := 0;
                                            full_c := 0;
                                            r_stage <= s4;
                                        else
                                            bc := 0;
                                            c := c + 1;
                                            r_stage <= s3i;
                                        end if;
                                    end if;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s3h;
                                end if;
                            
                            when s3i =>
                                if (bc=999999) then
                                    bc := 0;
                                    r_stage <= s3f;
                                else
                                    bc := bc + 1;
                                    r_stage <= s3i;
                                end if;
                                                                                        
--                              now we wait for the UART to send in the data to store into the SRAM
--                              the uart dev already handles the transaction and it gives us interrupts
--                              basically it sends us an IRQ request with the data we have to read.
                            when s4 =>
                                --  waiting for an interrupt by the uart or for the manual start signal for the cpu
                                leds_0 <= std_logic_vector(to_unsigned(5, 8));
                                if (sw(1 downto 0)="00") then
                                    r_stage <= s0;
                                else
                                    if (ss_uart_irq_0='1') then
                                        c := 0;
                                        --uart_irq_grant_0 <= '1';
                                        r_stage <= s5;
                                    else
                                        uart_irq_grant_0 <= '0';
                                        r_stage <= s4;
                                    end if;
                                end if;
                        
                            when s5 =>
                                --  now that grant is high, the uart will send the 4 bytes, so
                                leds_0 <= std_logic_vector(to_unsigned(6, 8)) or (std_logic_vector(to_unsigned(c, 4))&"0000");
                                if (ss_dev_out_drdy_0='1') then
                                    --  data is here
                                    isr_packet(((c+1)*8)-1 downto (c*8)) <= ss_dev_out_data_0;
                                    r_stage <= s6;
                                else
                                    --  waiting for the ISR data
                                    uart_irq_grant_0 <= '1';
                                    r_stage <= s5;
                                end if;
                            
                            when s6 =>
                                leds_0 <= std_logic_vector(to_unsigned(7, 8));                                
                                if (ss_dev_out_drdy_0='0') then
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
                                if ((ss_sync_0='1') and (ss_uart_irq_0='0')) then
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
                                if (ss_dev_out_drdy_0='1') then
                                    --  device has responded with the data I need, so:
                                    sram_packet(((bc+1)*8)-1 downto (bc*8)) <= ss_dev_out_data_0;
                                    r_stage <= s9;
                                else
                                    --  waiting
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s8;
                                end if;
                                        
                            when s9 =>
                                --  disengaging
                                leds_0 <= std_logic_vector(to_unsigned(10, 8));
                                if (ss_dev_out_drdy_0='0') then
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
                                --  writing to SRAM/EEPROM but wait
                                leds_0 <= std_logic_vector(to_unsigned(11, 8));
                                r_dev_in_cmd_0 <= '0';
                                r_dev_in_data_0 <= sram_packet(7 downto 0);
                                r_dev_in_addr_0 <= sram_packet(30 downto 8);
                                r_dev_in_keep_0 <= '0';
                                r_stage <= s11;
                            
                            when s11 =>
                                --  latching
                                leds_0 <= std_logic_vector(to_unsigned(12, 8));
                                if (ss_dev_out_drdy_0='1') then
                                    --  written to sram
                                    r_stage <= s12;
                                else
                                    --  latching data
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s11;
                                end if;
                            
                            when s12 =>
                                leds_0 <= std_logic_vector(to_unsigned(13, 8));
                                if (ss_dev_out_drdy_0='0') then
                                    --  we have written on the sram succesfully
                                    r_dev_in_cmd_0 <= '1';
                                    r_stage <= s13;
                                else
                                    --  latched everything
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s12;
                                end if;
                            
                            when s13 =>
                                leds_0 <= std_logic_vector(to_unsigned(14, 8));
                                if (ss_dev_out_drdy_0='1') then
                                    r_dev_in_data_0 <= ss_dev_out_data_0;
                                    r_stage <= s14;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s13;
                                end if;
                            
                            when s14 =>
                                leds_0 <= std_logic_vector(to_unsigned(15, 8));
                                if (ss_dev_out_drdy_0='0') then
                                    r_dev_in_cmd_0 <= '0';
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(131265, 23));
                                    r_stage <= s15;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s14;
                                end if;
                            
                            when s15 =>
                                leds_0 <= std_logic_vector(to_unsigned(16, 8));
                                if (ss_dev_out_drdy_0='1') then
                                    r_stage <= s16;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s15;
                                end if;
                                                        
                            when s16 =>
                                leds_0 <= std_logic_vector(to_unsigned(17, 8));
                                if (ss_dev_out_drdy_0='0') then
                                    uart_irq_grant_0 <= '0';
                                    r_stage <= s17;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s16;
                                end if;
                            
                            --  ora provo a mostrare sull'i2c l'avanzamento
                            when s17 =>
                                r_dev_in_cmd_0 <= '0';
                                if (tot_bytes=20) then
                                    tot_bytes := 0;
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(164362 + 8,23));
                                    r_dev_in_data_0 <= x"14";
                                    if (tt=x"23") then
                                        tt := x"5f";
                                    else
                                        tt := x"23";
                                    end if;                                        
                                else
                                    tot_bytes := tot_bytes + 1;
                                    r_dev_in_addr_0 <= std_logic_vector(to_unsigned(164362 + 4,23));
                                    r_dev_in_data_0 <= tt;
                                end if;
                                r_dev_in_keep_0 <= '0';
                                --  siamo pronti
                                r_stage <= s18;
                            
                            when s18 =>
                                if (ss_dev_out_drdy_0='1') then
                                    r_stage <= s19;
                                else
                                    r_dev_in_latch_0 <= '1';
                                    r_stage <= s18;
                                end if;
                            
                            when s19 =>
                                if (ss_dev_out_drdy_0='0') then
                                    r_stage <= s4;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage <= s19;
                                end if;

                            when others =>
                                r_stage <= s_IDLE;
                        end case;
                    end if;
                end process MAIN;
                            
    --  debug
    VIS:    process(sysClk)
            begin
                if (falling_edge(sysClk)) then
                    boh2 <= std_logic_vector(to_unsigned(cpu_output_port, 32)); --  cpu_output_port
                    --boh  <= std_logic_vector(to_unsigned(dbg_instr, 32));
                    --boh  <= std_logic_vector(to_unsigned(cpu_irq_isr, 32));
                    boh  <= std_logic_vector(to_unsigned(dbg_irq, 32));
                    boh3 <= std_logic_vector(to_unsigned(dbg_instr, 32));
                end if;
            end process VIS;
    
    with (sw) select                
--        leds <= std_logic_vector(to_unsigned(s_dbg_dev0_main, 8)) when "0000",          --  main loop state of the Demo device
--                std_logic_vector(to_unsigned(s_dbg_dev0_int, 8)) when "0001",           --  loop state of the Demo device's subbus                
--                std_logic_vector(to_unsigned(dbg_bridge_main, 8)) when "0110",          --  uart bridge main loop stage
--                std_logic_vector(to_unsigned(dbg_bridge_ext, 8)) when "0111",           --  uart bridge ext bus interface loop
--                std_logic_vector(to_unsigned(dbg_bridge_int, 8)) when "1000",           --  uart bridge int bus interface loop
--                std_logic_vector(to_unsigned(dbg_sdev_0, 8)) when "1001",               --  uart 0 main loop
--                std_logic_vector(to_unsigned(dbg_sdev_0_subbus, 8)) when "1010",        --  uart 0 subbus loop
--                std_logic_vector(to_unsigned(dbg_sdev_0_subbus_dev, 8)) when "1011",    --  uart 0 subbus int loop

        leds <= --std_logic_vector(to_unsigned(dbg_i2c_eeprom, 8)) when "1110",
                std_logic_vector(to_unsigned(dbg_sdev_1, 8)) when "1100",               --  uart 1 main loop
                std_logic_vector(to_unsigned(dbg_sdev_1_subbus, 8)) when "1101",        --  uart 1 subbus loop
                std_logic_vector(to_unsigned(dbg_sdev_1_subbus_dev, 8)) when "1110",    --  uart 10 subbus int loop
                --std_logic_vector(to_unsigned(dbg_trx, 8)) when "1100",
                --std_logic_vector(to_unsigned(dbg_hw, 8)) when "1101",
                --boh2(7 downto 0) when "1110",
                --std_logic_vector(to_unsigned(dbg_stage, 8)) when "1111",                --  i2c device 1 (lcd)     
                boh2(7 downto 0) when "0000",
                boh(7 downto 0) when "1000",
                leds_0 when others;                

    with (sw) select
        front_leds <=   std_logic_vector(to_unsigned(dbg_i2c_eeprom, 8)) when "1110",
                        std_logic_vector(to_unsigned(dbg_trx, 8)) when "1100",
                        std_logic_vector(to_unsigned(dbg_hw, 8)) when "1101",
                        std_logic_vector(to_unsigned(dbg_stage, 8)) when "1111",                --  i2c device 1 (lcd)
                        boh2(7 downto 0) when "0000",
                        boh(7 downto 0) when "1000",
                        boh3(7 downto 0) when "1001",
                        leds_0 when others; 

    front_red <= '0';
    front_green <= '0';
            
end Behavioral;
