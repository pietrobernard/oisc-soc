library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_uart_i2c is
    generic (
        --  uart options
        data_bit:       integer := 8;
        parity_bit:     integer range 0 to 1 := 0;  --  number of parity bits: 0 or 1
        stop_bit:       integer range 0 to 1 := 0;  --  number of stop bits: 1 or 2
        parity_typ:     integer range 0 to 3 := 0;  --  type of parity: 0 even, 1 odd, 2 mark, 3 space
        speed_bit:      integer := 9600             --  link speed
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
        --  debug signals
        serial_dat_dbg: out     std_logic;
        serial_clk_dbg: out     std_logic;
        leds:           out     std_logic_vector(7 downto 0)
    );
end top_uart_i2c;

architecture Behavioral of top_uart_i2c is
    signal s_data_rx: std_logic_vector(7 downto 0) := (others=>'0');
    signal s_rx: std_logic := '0';
    signal r_rx: std_logic := '0';
    signal r_data_tx: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_tx: std_logic := '0';
    signal s_tx: std_logic := '0';
    --  vediamo
    signal s_tx_done: std_logic := '0';
    signal s_rx_done: std_logic := '0';
    --  stuff
    signal s_out: std_logic := '0';
    signal rx_stage_dbg: std_logic_vector(3 downto 0) := (others=>'0');
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_WRITE_0, s_WRITE_1, s_WRITE_A, s_WRITE_D, s_READ_0, s_READ_1, s_READ_2, s_READ_3, s_END);
    signal r_stage: t_SM := s_INIT;
    signal r_jump: t_SM := s_INIT;
    
    type RAM_ARRAY is array (0 to 35 ) of std_logic_vector (7 downto 0);
    signal lcd_data: RAM_ARRAY := (
                                -- display initialization su 0x27
                                x"30",x"34",x"30",   --  0x03 << 4
                                x"30",x"34",x"30",   --  0x03 << 4
                                x"30",x"34",x"30",   --  0x03 << 4
                                x"20",x"24",x"20",   --  0x02 << 4
                                -- display function
                                -- 0x00 | 0x08 | 0x00 | 0x20 -> 0x28,0x30,0x28
                                x"20",x"24",x"20",
                                x"80",x"84",x"80",
                                -- display on/off
                                -- 0x04 | 0x02 | 0x01 | 0x08 -> 0x0F
                                x"00",x"04",x"00",
                                x"f0",x"f4",x"f0",
                                -- clear the display
                                -- 0x01
                                x"00",x"04",x"00",
                                x"10",x"14",x"10",
                                -- entry mode set
                                -- 0x06
                                x"00",x"04",x"00",
                                x"60",x"64",x"60"
                             );
    
    signal eeprom_data: RAM_ARRAY := (  x"00", x"00", x"aa",
                                        x"bb", x"cc", x"dd",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00",
                                        x"00", x"00", x"00"
                                     );
                             
    
    signal i2c_data_to: std_logic_vector(7 downto 0) := (others=>'0');
    signal i2c_data_from: std_logic_vector(7 downto 0) := (others=>'0');
    signal i2c_drdy: std_logic := '0';
    signal i2c_exec: std_logic := '0';
    signal i2c_done: std_logic := '0';
    
    signal i2c_address: std_logic_vector(6 downto 0) := (others=>'0');
    signal i2c_command: std_logic := '0';
    signal i2c_nbytes: std_logic_vector(7 downto 0) := (others=>'0');
    signal i2c_register: std_logic_vector(7 downto 0) := (others=>'0');
begin
    --  uart transceiver
    UART_TRX:   entity work.uart_trx(Behavioral)
        generic map (
            data_bit => data_bit,
            parity_bit => parity_bit,
            stop_bit => stop_bit,
            parity_typ => parity_typ,
            link_speed => speed_bit
        )
        port map (
            sysClk => sysClk,
            sysRstb => sysRstb,
            --  uart lines
            serial_input => serial_input,
            serial_output => s_out,
            --  input side
            data_in => r_data_tx,
            data_tx => r_tx,
            data_tx_done => s_tx,
            --  output side
            data_out => s_data_rx,
            data_rx => s_rx,
            data_rx_ack => r_rx,
            rx_stage_dbg => rx_stage_dbg
        );
    
    --  i2c transceiver
    I2C_TRX:    entity work.i2c_trx(Behavioral)
        port map (
            sysClk => sysClk,
            sysRstb => sysRstb,
            --  i2c bus
            i2c_scl => i2c_scl,
            i2c_sda => i2c_sda,
            --  i2c parameters
            bus_speed => "00",                  --  standard 100 kHz
            bus_cmd => i2c_command,                     --  write command
            dev_addr => i2c_address,             --  port expander for LCD control
            dev_reg_N => i2c_register,         --  no register
            dev_N_tr => i2c_nbytes,            --  number of bytes to send over : 42
            data_input => i2c_data_to,          --  data to the i2c bus
            start_send => i2c_exec,
            done_send => i2c_done,
            data_output => i2c_data_from,
            drdy => i2c_drdy
        );
    
           
    --  main process
    MAIN:   process(sysClk)
                variable idx: integer := 0;
                variable bC: integer := 0;
                variable nbytes_reg: integer := 0;
                variable nbytes_data: integer := 36;
                variable nbytes: integer := 0;
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>   
                                --i2c_address <= "1010000";       --  indirizzo della eeprom7
                                i2c_address <= "0100111";                                       --  indirizzo dell'LCD
                                i2c_command <= '0';                                             --  comando di scrittura
                                i2c_nbytes <= std_logic_vector(to_unsigned(nbytes_data,8));     --  byte da scrivere (+1 se con registro specificato)
                                i2c_register <= std_logic_vector(to_unsigned(nbytes_reg,8));    --  numero bytes indirizzo registro periferica
                                i2c_exec <= '0';
                                idx := 0;
                                if (nbytes_reg=0) then
                                    r_stage <= s_WRITE_D;
                                else
                                    r_stage <= s_WRITE_A;
                                end if;
                                                    
                            --  SCRITTURA
                            when s_WRITE_0 =>
                                --i2c_data_to <= eeprom_data(idx);
                                i2c_data_to <= (lcd_data(idx) or x"08");
                                i2c_exec <= '0';
                                if (i2c_done='0') then
                                    r_stage <= s_WRITE_1;
                                else
                                    r_stage <= s_WRITE_0;
                                end if;
                            
                            when s_WRITE_1 =>
                                i2c_exec <= '1';
                                if (i2c_done='1') then
                                    if (bC=(nbytes-1)) then
                                        --  scrittura completata
                                        bC := 0;
                                        r_stage <= r_jump;
                                    else
                                        --  ancora da scrivere
                                        bC := bC + 1;
                                        idx := idx + 1;
                                        r_stage <= s_WRITE_0;
                                    end if;
                                else
                                    r_stage <= s_WRITE_1;
                                end if;
                            
                            when s_WRITE_A =>
                                nbytes := nbytes_reg;
                                bC := 0;
                                idx := 0;
                                r_jump <= s_WRITE_D;
                                r_stage <= s_WRITE_0;
                            
                            when s_WRITE_D =>
                                nbytes := nbytes_data;
                                bC := 0;
                                if (nbytes_reg=0) then
                                    idx := 0;
                                else
                                    idx := idx + 1;
                                end if;
                                r_jump <= s_END;
                                r_stage <= s_WRITE_0;
                            
                            --  LETTURA
                            when s_READ_0 =>
                                i2c_data_to <= eeprom_data(idx);
                                i2c_command <= '0';
                                i2c_exec <= '0';
                                if (i2c_done='0') then
                                    r_stage <= s_READ_1;
                                else
                                    r_stage <= s_READ_0;
                                end if;
                            
                            when s_READ_1 =>
                                i2c_exec <= '1';
                                if (i2c_done='1') then
                                    if (idx=1) then
                                        --  byte indirizzo scritti
                                        idx := 0;
                                        i2c_command <= '1';
                                        r_stage <= s_READ_2;
                                    else
                                        --  continuo a scrivere byte indirizzo
                                        idx := idx + 1;
                                        r_stage <= s_READ_0;
                                    end if;
                                else
                                    r_stage <= s_READ_1;
                                end if;
                            
                            when s_READ_2 =>
                                --  dopo la scrittura dell'indirizzo, il sistem automaticamente fornisce il primo byte letto
                                if (i2c_drdy='1') then
                                    --  il byte e' arrivato
                                    leds <= i2c_data_from;
                                    --  adesso posso andare avanti
                                    if (idx=(nbytes-1)) then
                                        --  lettura finita
                                        r_stage <= s_END;
                                    else
                                        --  devo ancora leggere roba
                                        idx := idx + 1;
                                        r_stage <= s_READ_3;
                                    end if;
                                else
                                    --  attendiamo la lettura del byte
                                    i2c_exec <= '1';
                                    r_stage <= s_READ_2;
                                end if;
                            
                            when s_READ_3 =>
                                i2c_exec <= '0';
                                if (i2c_drdy='0') then
                                    r_stage <= s_READ_2;
                                else
                                    r_stage <= s_READ_3;
                                end if;
                                
                            
                            --  FINE
                            when s_END =>
                                i2c_exec <= '0';
                                if ((i2c_done='0') and (i2c_drdy='0')) then
                                    r_stage <= s_IDLE;
                                else
                                    r_stage <= s_END;
                                end if;
                                
                            
                            when others =>
                                r_stage <= r_stage;
                        end case;
                    end if;
                end if;
            end process MAIN;

    --  assignments
    serial_dat_dbg <= s_out;
    serial_output <= s_out;
    serial_clk_dbg <= '0';
    --leds(7 downto 4) <= rx_stage_dbg;
    
    
    
end Behavioral;
