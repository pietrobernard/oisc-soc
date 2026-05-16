library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hwdrv_UART is
    generic (
        --  bus topology
        data_width: integer := 8;
        ndevs: natural := 8
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        
        --  HARDWARE LINES
        serial_input: in std_logic;
        serial_output: out std_logic;
        
        --  INTERFACE WITH HARDWARE BUS
        --  system bus interface signals
        bus_request: in std_logic_vector(ndevs-1 downto 0);
        bus_grant: out std_logic_vector(ndevs-1 downto 0);
        bus_busy: out std_logic;
        --  output databus lanes
        data_out: out std_logic_vector(data_width-1 downto 0);
        data_drdy: out std_logic;
        data_ack: in std_logic;
        --  input databus lanes
        data_in: in std_logic_vector(data_width-1 downto 0);
        data_latch: in std_logic;
        data_in_keep: in std_logic;
        data_done: out std_logic
    );
end hwdrv_UART;

architecture Behavioral of hwdrv_UART is
    --  control signals
    signal r_uart_data_in: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_uart_data_tx: std_logic := '0';
    signal s_uart_tx_done: std_logic;
    signal s_uart_data_out: std_logic_vector(7 downto 0);
    signal s_uart_data_rx: std_logic;
    signal r_uart_rx_ack: std_logic := '0';
    
    --  sampling signals
    signal ss_uart_tx_done: std_logic := '0';
    signal ss_uart_data_out: std_logic_vector(7 downto 0) := (others=>'0');
    signal ss_uart_data_rx: std_logic := '0';
    
    --  driving signals for interface
    signal r_int_data_out: std_logic_vector(7 downto 0) := (others=>'0');
    signal r_int_data_drdy: std_logic := '0';
    signal r_int_data_done: std_logic := '0';
    
    --  sampling signals for interface
    signal ss_int_data_ack: std_logic := '0';
    signal ss_int_data_keep: std_logic := '0';
    signal ss_int_data_in: std_logic_vector(7 downto 0) := (others=>'0');
    signal ss_int_data_latch: std_logic := '0';
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_RX_0, s_RX_1, s_RX_2, s_RX_3, s_TX_0, s_TX_1, s_TX_2, s_TX_3, s_TX_4);
    signal r_stage: t_SM := s_INIT;
    
    --  synchronizer
    signal ss_sync_0: std_logic := '0';
begin
    --  assignments
    data_out <= r_int_data_out;
    data_drdy <= r_int_data_drdy;
    data_done <= r_int_data_done;

    --  hardware access arbiter
    HWARB:  entity work.bus_arb(Behavioral)
                generic map (
                    n_rq_lines => ndevs
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  request lines
                    rq_lines => bus_request,
                    grant_lines => bus_grant,
                    busy => bus_busy
                );

    --  UART TRANSCEIVER
    HWUART: entity work.uart_trx(Behavioral)
                generic map (
                    data_bit => 8,
                    parity_bit => 0,
                    stop_bit => 0,
                    parity_typ => 0,
                    link_speed => 9600
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  hardware lines
                    serial_input => serial_input,
                    serial_output => serial_output,
                    --  input side
                    data_in => r_uart_data_in,
                    data_tx => r_uart_data_tx,
                    data_tx_done => s_uart_tx_done,
                    --  output side
                    data_out => s_uart_data_out,
                    data_rx => s_uart_data_rx,
                    data_rx_ack => r_uart_rx_ack
                );
    
    --  Sampling and Main process
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_int_data_ack <= '0';
                                ss_int_data_in <= (others=>'0');
                                ss_int_data_latch <= '0';
                                ss_sync_0 <= '0';
                                
                            when s_IDLE =>
                                --  new data from the uart lines
                                ss_uart_data_out <= s_uart_data_out;
                                ss_uart_data_rx <= s_uart_data_rx;
                                --  new data from the internal bus
                                ss_int_data_in <= data_in;
                                ss_int_data_keep <= data_in_keep;
                                ss_int_data_latch <= data_latch;
                                --  synchro
                                ss_sync_0 <= '0';
                                                       
                            when s_RX_1 =>
                                ss_uart_data_rx <= s_uart_data_rx;
                            
                            when s_RX_2 =>
                                ss_int_data_ack <= data_ack;
                        
                            when s_RX_3 =>
                                ss_int_data_ack <= data_ack;
                                         
                            when s_TX_0 =>
                                ss_sync_0 <= '0';
                                         
                            when s_TX_1 =>
                                ss_uart_tx_done <= s_uart_tx_done;
                        
                            when s_TX_2 =>
                                ss_uart_tx_done <= s_uart_tx_done;
                        
                            when s_TX_3 =>
                                ss_int_data_latch <= data_latch;
                        
                            when s_TX_4 =>
                                ss_int_data_in <= data_in;
                                ss_int_data_keep <= data_in_keep;
                                ss_int_data_latch <= data_latch;
                                ss_sync_0 <= '1';
                        
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:       process(sysClk)
                    variable cond: std_logic_vector(1 downto 0) := "00";
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            --  reset
                            r_stage <= s_INIT;
                        else
                            --  state machine
                            case (r_stage) is
                                when s_INIT =>
                                    r_uart_rx_ack <= '0';
                                    r_int_data_drdy <= '0';
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  surveying both the sub-bus and the uart rx line
                                    cond := (ss_int_data_latch & ss_uart_data_rx);
                                    case (cond) is
                                        --  remain here
                                        when "00" =>
                                            r_stage <= s_IDLE;
                                    
                                        --  new data incoming from the serial port
                                        when "01" =>
                                            r_stage <= s_RX_0;
                                        
                                        --  a sub-device wants to gain access to the uart tx line
                                        when "10"|"11" =>
                                            r_stage <= s_TX_0;
                                        
                                        when others =>
                                            r_stage <= s_IDLE;
                                    end case;
                            
                                when s_RX_0 =>
                                    --  data from the serial port, so
                                    r_int_data_out <= ss_uart_data_out;
                                    r_uart_rx_ack <= '1';
                                    r_stage <= s_RX_1;
                            
                                when s_RX_1 =>
                                    if (ss_uart_data_rx='0') then
                                        r_uart_rx_ack <= '0';
                                        r_int_data_drdy <= '1';
                                        r_stage <= s_RX_2;
                                    else
                                        r_stage <= s_RX_1;
                                    end if;
                                
                                when s_RX_2 =>
                                    if (ss_int_data_ack='1') then
                                        r_int_data_drdy <= '0';
                                        r_int_data_out <= (others=>'0');
                                        r_stage <= s_RX_3;
                                    else
                                        r_stage <= s_RX_2;
                                    end if;
                            
                                when s_RX_3 =>
                                    if (ss_int_data_ack='0') then
                                        r_stage <= s_IDLE;
                                    else
                                        r_stage <= s_RX_3;
                                    end if;
                            
                                when s_TX_0 =>
                                    --  access to the transmitter, so
                                    r_uart_data_in <= ss_int_data_in;
                                    r_uart_data_tx <= '1';
                                    r_stage <= s_TX_1;
                            
                                when s_TX_1 =>
                                    if (ss_uart_tx_done='1') then
                                        --  it has finished the transmission, hence
                                        r_int_data_done <= '1';
                                        r_uart_data_tx <= '0';
                                        r_stage <= s_TX_2;
                                    else
                                        r_stage <= s_TX_1;
                                    end if;
                            
                                when s_TX_2 =>
                                    if (ss_uart_tx_done='0') then
                                        r_stage <= s_TX_3;
                                    else
                                        r_stage <= s_TX_2;
                                    end if;
                            
                                when s_TX_3 =>
                                    if (ss_int_data_latch='0') then
                                        r_int_data_done <= '0';
                                        if (ss_int_data_keep='1') then
                                            r_stage <= s_TX_4;
                                        else
                                            r_stage <= s_IDLE;
                                        end if;
                                    else
                                        r_stage <= s_TX_3;
                                    end if;
                            
                                when s_TX_4 =>
                                    if ((ss_sync_0='1') and (ss_int_data_latch='1')) then
                                        r_stage <= s_TX_0;
                                    else
                                        r_stage <= s_TX_4;
                                    end if;
                            
                                when others =>
                                    r_stage <= s_IDLE;
                            end case;
                        end if;
                    end if;
                end process MAIN;

end Behavioral;
