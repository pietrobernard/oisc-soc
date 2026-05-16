library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_uart is
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
        --  debug signals
        serial_dat_dbg: out     std_logic;
        serial_clk_dbg: out     std_logic;
        leds:           out     std_logic_vector(7 downto 0)
    );
end top_uart;

architecture Behavioral of top_uart is
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
    type t_SM is (s_INIT, s_IDLE, s_ECHO_0, s_ECHO_1, s_ECHO_2);
    signal r_stage: t_SM := s_INIT;
    
    type RAM_ARRAY is array (0 to 15 ) of std_logic_vector (7 downto 0);
    signal RAM: RAM_ARRAY := (
                               x"43",x"69",x"61",x"6f",-- 0x00: 
                               x"20",x"63",x"6f",x"6d",-- 0x04: 
                               x"65",x"20",x"76",x"61",-- 0x08: 
                               x"3f",x"20",x"20",x"20" -- 0x0C:                               
                             );
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

    
    --  main process
    MAIN:   process(sysClk)
                
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>                                
                                r_data_tx <= (others=>'0');
                                r_tx <= '0';
                                r_rx <= '0';
                                r_stage <= s_IDLE;
                        
                            when s_IDLE =>
                                if (s_rx='1') then
                                    --  receiving data
                                    r_data_tx <= s_data_rx;
                                    r_rx <= '1';
                                    r_stage <= s_ECHO_0;
                                else
                                    r_stage <= s_IDLE;
                                end if;
                            
                            when s_ECHO_0 =>
                                if (s_rx='0') then
                                    r_rx <= '0';
                                    r_tx <= '1';
                                    r_stage <= s_ECHO_1;
                                else
                                    r_stage <= s_ECHO_0;
                                end if;
                            
                            when s_ECHO_1 =>
                                if (s_tx='1') then
                                    r_tx <= '0';
                                    r_stage <= s_ECHO_2;
                                else
                                    r_stage <= s_ECHO_1;
                                end if;
                            
                            when s_ECHO_2 =>
                                if (s_tx='0') then
                                    r_stage <= s_IDLE;
                                else
                                    r_stage <= s_ECHO_2;
                                end if;
                            
                            
                            
                        end case;
                    end if;
                end if;
            end process MAIN;

    --  assignments
    serial_dat_dbg <= s_out;
    serial_output <= s_out;
    serial_clk_dbg <= '0';
    leds(7 downto 4) <= rx_stage_dbg;
    
    
    
end Behavioral;
