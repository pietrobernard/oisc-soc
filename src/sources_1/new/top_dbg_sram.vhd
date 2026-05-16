library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_dbg_sram is
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
        sw0:            in      std_logic
    );
end top_dbg_sram;

architecture Behavioral of top_dbg_sram is
    signal r_dir: std_logic := '0';
    signal r_data_to: std_logic_vector(7 downto 0);
    signal s_data_from: std_logic_vector(7 downto 0);
    signal r_ral: std_logic := '1';
    signal r_rah: std_logic := '1';
    signal r_oe: std_logic := '1';
    signal r_we: std_logic := '1';
    
    type t_SM is (s_0, s_1, s_2, s_3, s_4, s_5, s_6, s_7, s_8, s_9);
    signal r_stage: t_SM := s_0;
    
    --  timing constants in unit of clock cycles (10 ns)
    constant latch_tsu: natural := 4;
    constant latch_th: natural := 2;
begin

    --  driving signals
    SRAM_TRXDIR <= r_dir;
    SRAM_TRXOE <= '0';
    RAL_L <= r_ral;
    RAL_H <= r_rah;
    SRAM_CE <= '0';
    SRAM_OE <= r_oe;
    SRAM_WE <= r_we;
    SRAM_LH <= '0';

    --  assignments to unused ports
    serial_output <= '1';
    i2c_scl <= '1';
    i2c_sda <= '1';
    vga_R <= (others=>'0');
    vga_G <= (others=>'0');
    vga_B <= (others=>'0');
    vga_HS <= '1';
    vga_VS <= '1';
    portA <= (others=>'Z');
    dackA <= '0';
    
    --  now to try and work with the sram, so
    SRAM_PORT:  entity work.inout_port(Behavioral)
                generic map (
                    nbits => 8
                ) port map (
                    io => DATA,
                    data_to => r_data_to,
                    data_from => s_data_from,
                    dir => r_dir
                );

    --  provo intanto a settare un indirizzo per vedere cosa succede
    MAIN:   process(sysClk)
                variable c: natural := 0;
            begin
                if (rising_edge(sysClk)) then
                    case (r_stage) is
                        when s_0 =>
                            r_dir <= '1';
                            r_data_to <= std_logic_vector(to_unsigned(12, 8));                            
                            c := 0;
                            leds <= (others=>'0');
                            r_stage <= s_1;
                                                                        
                        when s_1 =>
                            if (c=(latch_tsu-1)) then
                                c := 0;
                                r_ral <= '0';
                                r_stage <= s_2;
                            else
                                c := c + 1;
                                r_stage <= s_1;
                            end if;
                    
                        when s_2 =>
                            if (c=(latch_th-1)) then
                                c := 0;
                                r_data_to <= std_logic_vector(to_unsigned(127,8));
                                r_stage <= s_3;
                            else
                                c := c + 1;
                                r_stage <= s_2;
                            end if;
                        
                        when s_3 =>
                            if (c=(latch_tsu-1)) then
                                c := 0;
                                r_rah <= '0';
                                r_stage <= s_4;
                            else
                                c := c + 1;
                                r_stage <= s_3;
                            end if;
                        
                        when s_4 =>
                            if (c=(latch_th-1)) then
                                c := 0;
                                r_data_to <= std_logic_vector(to_unsigned(48,8));
                                r_stage <= s_5;
                            else
                                c := c + 1;
                                r_stage <= s_4;
                            end if;
                                                     
                        when s_5 =>
                            if (c=5) then
                                r_we <= '1';
                                c := 0;
                                r_stage <= s_6;
                            else
                                c := c + 1;
                                r_we <= '0';
                                r_stage <= s_5;
                            end if;
                        
                        when s_6 =>
                            --  adesso provo a leggere dopo aver scritto. L'indirizzo resta quello
                            if (c=5) then
                                leds <= s_data_from;
                                r_oe <= '1';
                                r_dir <= '1';
                                r_stage <= s_7;
                            else
                                c := c + 1;
                                r_dir <= '0';
                                r_oe <= '0';
                                r_stage <= s_6;
                            end if;
                        
                        when s_7 =>
                            r_stage <= s_7;
                            
                        
                        when others =>
                            r_stage <= s_7;
                    end case;
                end if;
            end process MAIN;


end Behavioral;

