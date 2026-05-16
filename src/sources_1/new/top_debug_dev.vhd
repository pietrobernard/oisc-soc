library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
--  changelog: 4/4/25
--  in bus_interface and dev source files I edited some ss double registering
--  in order to reduce the amount of logic levels and thus reduce the total negative slack in high fanout conditions.
entity top_debug_dev is
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
end top_debug_dev;

architecture Behavioral of top_debug_dev is
    --  bus arbiter lines
    signal bus_rq_lines: std_logic_vector(7 downto 0) := (others=>'0');
    signal bus_grant_lines: std_logic_vector(7 downto 0);
    signal bus_busy: std_logic;
    
    --  system bus
    signal bus_strobe_M: std_logic;
    signal bus_strobe_S: std_logic;
    signal bus_keep: std_logic;
    signal bus_lines: std_logic_vector(31 downto 0);
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s0, s1, s2, s3, s4, s5, s6, s7, s8, s8a, s8b, s8c, s9, s10, s11, s12, s13, s14, s15, s16, s17, s18, s19, s20);
    signal r_stage_0: t_SM := s_INIT;
    signal r_stage_1: t_SM := s_INIT;
    
    --  interfaces control signals
    signal r_dev_in_cmd_0: std_logic := '0';
    signal r_dev_in_addr_0: std_logic_vector(22 downto 0) := (others=>'0');
    signal r_dev_in_data_0: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_dev_in_keep_0: std_logic := '0';
    signal r_dev_in_latch_0: std_logic := '0';
    signal s_dev_out_cmd_0: std_logic;
    signal s_dev_out_addr_0: std_logic_vector(22 downto 0) := (others=>'0');
    signal s_dev_out_data_0: std_logic_vector(7 downto 0) := (others=>'0');
    signal s_dev_out_drdy_0: std_logic;
    signal s_dev_out_done_0: std_logic;
    signal s_dev_err_0: std_logic;
    signal s_dev_chg_0: std_logic;
    signal dbg_0: natural;
    
    signal r_dev_in_cmd_1: std_logic := '0';
    signal r_dev_in_addr_1: std_logic_vector(22 downto 0) := (others=>'0');
    signal r_dev_in_data_1: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_dev_in_keep_1: std_logic := '0';
    signal r_dev_in_latch_1: std_logic := '0';
    signal s_dev_out_cmd_1: std_logic;
    signal s_dev_out_addr_1: std_logic_vector(22 downto 0) := (others=>'0');
    signal s_dev_out_data_1: std_logic_vector(7 downto 0) := (others=>'0');
    signal s_dev_out_drdy_1: std_logic;
    signal s_dev_out_done_1: std_logic;
    signal s_dev_err_1: std_logic;
    signal s_dev_chg_1: std_logic;
    signal dbg_1: natural;
    
    signal leds_0: std_logic_vector(7 downto 0) := (others=>'0');
    signal dbg_dev_0: natural;
    signal dbg_dev_1: natural;
    
begin    
    --  line terminations
    bus_rq_lines(7 downto 2) <= (others=>'0');
    
    --  bus arbiter
    BUS_ARB:    entity work.bus_arb(Behavioral)
                generic map (
                    n_rq_lines => 8
                ) port map (
                    sysClk => sysClk,
                    sysRstb => '1',
                    --  request lines
                    rq_lines => bus_rq_lines,
                    grant_lines => bus_grant_lines,
                    busy => bus_busy
                );
                
    --  demo device to interface here
    DEV_DEM0:   entity work.dev_v2(Behavioral)
                generic map (
                    dev_mem_begin => 0,
                    dev_mem_end => 200
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  bus lines and logic
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    --  bus arbiter
                    bus_rq => bus_rq_lines(0),
                    bus_grant => bus_grant_lines(0),
                    bus_busy => bus_busy,
                    --  interface addr/data
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
                    dbg_stage => dbg_0
                );
    
    DEV_DEM1:   entity work.dev_v2(Behavioral)
                generic map (
                    dev_mem_begin => 201,
                    dev_mem_end => 400
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  bus lines and logic
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    --  bus arbiter
                    bus_rq => bus_rq_lines(1),
                    bus_grant => bus_grant_lines(1),
                    bus_busy => bus_busy,
                    --  interface addr/data
                    dev_in_cmd => r_dev_in_cmd_1,
                    dev_in_addr => r_dev_in_addr_1,
                    dev_in_data => r_dev_in_data_1,
                    dev_in_keep => r_dev_in_keep_1,
                    dev_in_latch => r_dev_in_latch_1,
                    dev_out_cmd => s_dev_out_cmd_1,
                    dev_out_addr => s_dev_out_addr_1,
                    dev_out_data => s_dev_out_data_1,
                    dev_out_drdy => s_dev_out_drdy_1,
                    dev_out_done => s_dev_out_done_1,
                    dev_err => s_dev_err_1,
                    dev_chg => s_dev_chg_1,
                    --  debug
                    dbg_stage => dbg_1
                );
                
    MAIN_0:     process(sysClk)
                    variable c0: natural := 0;
                    variable c1: natural := 0;
                    variable c: natural := 0;
                    variable cond: std_logic_vector(1 downto 0) := "00";
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage_0) is
                            when s_INIT =>
                                c := 0;
                                r_stage_0 <= s_IDLE;
                            
                            when s_IDLE =>
                                r_dev_in_cmd_0 <= '1';
                                r_dev_in_addr_0 <= std_logic_vector(to_unsigned(264, 23));
                                r_dev_in_data_0 <= (others=>'0');
                                r_dev_in_keep_0 <= '0';
                                r_stage_0 <= s0;
                            
                            when s0 =>
                                cond := (s_dev_err_0 & s_dev_out_drdy_0);
                                case (cond) is
                                    when "00" =>
                                        --  waiting
                                        r_dev_in_latch_0 <= '1';
                                        r_stage_0 <= s0;
                                    
                                    when "01" =>
                                        --  done!
                                        leds_0 <= x"f0";
                                        r_stage_0 <= s1;
                                    
                                    when "10" =>
                                        --  errore
                                        r_stage_0 <= s6;
                                    
                                    when others =>
                                        r_stage_0 <= s0;
                                end case;
                            
                            when s1 =>
                                if (s_dev_out_drdy_0='0') then
                                    r_stage_0 <= s2;
                                else
                                    r_dev_in_latch_0 <= '0';
                                    r_stage_0 <= s1;
                                end if;
                            
                            when s2 =>
                                leds_0 <= x"d0";
                                r_stage_0 <= s2;
                                
                            
                            
                                
                            when others =>
                                r_stage_0 <= s_IDLE;
                        end case;
                    end if;
                end process MAIN_0;

    MAIN_1:     process(sysClk)
                    variable c0: natural := 0;
                    variable c1: natural := 0;
                    variable myreg: natural := 0;
                    variable done: std_logic_vector(1 downto 0) := "00";
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage_1) is
                            when s_INIT =>
                                c0 := 0;
                                c1 := 0;
                                r_stage_1 <= s_IDLE;
                            
                            when s_IDLE =>
                                if (s_dev_chg_1='1') then
                                    r_stage_1 <= s0;
                                else
                                    --  aspetto registro
                                    r_stage_1 <= s_IDLE;
                                end if;
                            
                            when s0 =>
                                if (s_dev_chg_1='0') then
                                    r_dev_in_latch_1 <= '0';
                                    r_stage_1 <= s_IDLE;
                                else
                                    r_dev_in_latch_1 <= '1';
                                    r_stage_1 <= s0;
                                end if;
                            
                            when others =>
                                r_stage_1 <= s_IDLE;
                        end case;
                    end if;
                end process MAIN_1;
                            
    --  assignments for vga
    vga_R <= (others=>'0');
    vga_G <= (others=>'0');
    vga_B <= (others=>'0');
    vga_HS <= '1';
    vga_VS <= '1';
    
    --  debug lines
    dbg_S <= '0';
    dbg_M <= '0';
    
    with (sw) select
        leds <= std_logic_vector(to_unsigned(dbg_0, 8)) when "0000",
                std_logic_vector(to_unsigned(dbg_1, 8)) when "0001",
                std_logic_vector(to_unsigned(dbg_dev_0, 8)) when "0010",
                std_logic_vector(to_unsigned(dbg_dev_1, 8)) when "0011",
                leds_0 when others;
        
end Behavioral;
