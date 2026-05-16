library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  transmit module for the UART transceiver
--  a data packet is sent down the line when the 'tx_start' signal is pulled high.
--  that signal latches the input 'tx_data' into the outgoing register.
--  once the transmission completes, the 'tx_done' signal goes high and the transmitter
--  waits until the 'tx_start' signal goes low again before accepting a new data packet.
entity uTX is
    generic (
        data_bit:       integer := 8;
        parity_bit:     integer range 0 to 1 := 0;  --  number of parity bits: 0 or 1
        stop_bit:       integer range 0 to 1 := 0;  --  number of stop bits: 1 or 2
        parity_typ:     integer range 0 to 3 := 0;  --  type of parity: 0 even, 1 odd, 2 mark, 3 space
        link_speed:     integer := 9600
    );
    port (
        sysClk:     in std_logic;
        sysRstb:    in std_logic;
        --  uart related
        serial_out: out std_logic;
        --  communication module
        tx_data:    in  std_logic_vector(7 downto 0);
        tx_start:   in  std_logic;
        tx_done:    out std_logic
    );
end uTX;

architecture Behavioral of uTX is
    --  constants
    constant packet_size: integer := (1 + data_bit + parity_bit + stop_bit + 1);
    constant full_pulse_w: integer := 100_000_000 / link_speed;
    constant half_pulse_w: integer := full_pulse_w / 2;
    
    --  line driver
    signal r_serial_out: std_logic := '1';
    signal s_parity_bits: std_logic_vector(3 downto 0) := (others=>'0');
    
    --  data packet
    signal s_data_packet: std_logic_vector(11 downto 0) := (others => '0');
    signal r_data_packet: std_logic_vector(11 downto 0) := (others => '0');
    signal r_tx_start: std_logic := '0';
    signal r_tx_done: std_logic := '0';
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_START_TX, s_NEXT_TX, s_DONE_TX);
    signal r_stage: t_SM := s_INIT;
begin
    --  parity generator
    PGEN:   entity work.parity_generator(Behavioral)
        port map (
            data_input => tx_data,
            parity_bits => s_parity_bits
        );
    
    --  packet builder
    PBLD:   entity work.pkt_builder(Behavioral)
        generic map (
            data_bit => data_bit,
            parity_bit => parity_bit,
            stop_bit => stop_bit
        )
        port map (
            data_in => tx_data,
            parity => s_parity_bits(parity_typ),
            data_out => s_data_packet
        );
    
    --  sampler
    SAMPLER:    process(sysClk)
    
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_tx_start <= '0';
                            r_data_packet <= (others=>'0');
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_tx_start <= '0';
                                    r_data_packet <= (others=>'0');
                                
                                when s_IDLE =>
                                    r_tx_start <= tx_start;
                                    r_data_packet <= s_data_packet;
                                                                    
                                when s_DONE_TX =>
                                    r_tx_start <= tx_start;
                                
                                when others =>
                                    r_tx_start <= r_tx_start;
                                    r_data_packet <= r_data_packet;
                            end case;
                        end if;
                    end if;
                end process SAMPLER;
                
    --  processo
    UART_TX:    process(sysClk)
                    variable clockCounter: integer := 0;
                    variable bitIndex: integer := 0;  
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            --  system reset
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_serial_out <= '1';
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    --  waiting for a packet to be sent
                                    clockCounter := 0;
                                    bitIndex := 0;
                                    r_tx_done <= '0';
                                    r_serial_out <= '1';
                                    if (r_tx_start='1') then
                                        --  have to send data
                                        r_stage <= s_START_TX;
                                    else
                                        --  need to wait
                                        r_stage <= s_IDLE;
                                    end if;
                            
                                when s_START_TX =>
                                    --  transmitting a bit
                                    r_serial_out <= r_data_packet(bitIndex);
                                    if (clockCounter=(full_pulse_w-1)) then
                                        clockCounter := 1;
                                        r_stage <= s_NEXT_TX;
                                    else
                                        clockCounter := clockCounter + 1;
                                        r_stage <= s_START_TX;
                                    end if;
                            
                                when s_NEXT_TX =>
                                    --  checking
                                    if (bitIndex=(packet_size-1)) then
                                        --  done transmitting
                                        r_tx_done <= '1';
                                        r_serial_out <= '1';
                                        r_stage <= s_DONE_TX;
                                    else
                                        --  still need to transmit
                                        r_tx_done <= '0';
                                        bitIndex := bitIndex + 1;
                                        r_stage <= s_START_TX;
                                    end if;
                            
                                when s_DONE_TX =>
                                    if (r_tx_start='0') then
                                        r_tx_done <= '0';
                                        r_stage <= s_IDLE;
                                    else
                                        r_tx_done <= '1';
                                        r_stage <= s_DONE_TX;
                                    end if;
                            end case;
                        end if;
                    end if;
                end process UART_TX;

    --  serial line driver
    serial_out <= r_serial_out;
    tx_done <= r_tx_done;
end Behavioral;
