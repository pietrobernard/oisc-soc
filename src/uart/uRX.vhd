library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uRX is
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
        serial_in:  in std_logic;
        --  communication module
        rx_data:    out std_logic_vector(7 downto 0);
        parity_chk: out std_logic;
        new_data:   out std_logic;
        data_ack:   in std_logic;
        --  debug
        stage_dbg:  out std_logic_vector(3 downto 0)
    );
end uRX;

architecture Behavioral of uRX is
    --  constants
    constant packet_size: integer := (1 + data_bit + parity_bit + stop_bit + 1);
    constant full_pulse_w: integer := 100_000_000 / link_speed;
    constant half_pulse_w: integer := full_pulse_w / 2;
    
    --  signals
    signal r_input_bits: std_logic_vector((packet_size-1) downto 0) := (others=>'0');
    signal s_pcheck: std_logic := '0';
    signal r_serial_input: std_logic := '0';
    signal r_data_ack: std_logic := '0';
    signal r_new_data: std_logic := '0';
    
    --  synchronizers
    signal r_serial_in_sync: std_logic := '0';
    
    --  state machine type
    type t_SM is (s_INIT, s_IDLE, s_WAIT_F, s_WAIT_H, s_SAMPLE, s_DATA_WAIT, s_DATA_ACK);
    signal r_stage: t_SM := s_INIT;
    
    --  debug
    signal r_stage_dbg: std_logic_vector(3 downto 0) := (others=>'0');
begin
    --  UART receiver module
    PCHECK: entity work.paritygen(Behavioral)
            port map (
                data => r_input_bits(9 downto 1),
                parity_type => std_logic_vector(to_unsigned(parity_typ, 2)),
                pcheck => s_pcheck
            );

    --  SAMPLER and Synchronizer
    SAMPLER:    process (sysClk)
            
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_serial_input <= '0';
                            r_data_ack <= '0';
                        else
                            r_serial_in_sync <= serial_in;
                            r_serial_input <= r_serial_in_sync;
                            r_data_ack <= data_ack;
                        end if;
                    end if;
                end process SAMPLER;

    --  RECEIVER
    UART_RX:    process (sysClk)
                    --  contatore di cicli di clock e indice di bit
                    variable clockCounter: integer := 0;
                    variable bitIndex: integer := 0;  
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            --  system reset
                            r_stage <= s_INIT;
                            r_new_data <= '0';
                            r_input_bits <= (others=>'0');
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    --  waiting for serial line to be high
                                    r_stage_dbg <= std_logic_vector(to_unsigned(0,4));
                                    if (r_serial_input='1') then
                                        r_stage <= s_IDLE;
                                    else
                                        r_stage <= s_INIT;
                                    end if;
                                
                                when s_IDLE =>
                                    --  waiting for a transmission to be received
                                    r_stage_dbg <= std_logic_vector(to_unsigned(1,4));
                                    r_new_data <= '0';
                                    r_input_bits <= (others=>'0');
                                    if (r_serial_input='0') then
                                        --  a high to low transition occurred => start bit
                                        clockCounter := 1;
                                        r_stage <= s_WAIT_H;
                                    else
                                        clockCounter := 0;
                                        r_stage <= s_IDLE;
                                    end if;
                            
                                when s_WAIT_H =>
                                    --  waiting for half a period
                                    r_stage_dbg <= std_logic_vector(to_unsigned(2,4));
                                    if (clockCounter=(half_pulse_w-1)) then
                                        clockCounter := 1;
                                        bitIndex := 1;
                                        r_stage <= s_WAIT_F;
                                    else
                                        clockCounter := clockCounter + 1;
                                        bitIndex := 0;
                                        r_stage <= s_WAIT_H;
                                    end if;
                                
                                when s_WAIT_F =>
                                    --  waiting for a full period
                                    r_stage_dbg <= std_logic_vector(to_unsigned(3,4));
                                    if (clockCounter=(full_pulse_w-1)) then
                                        clockCounter := 0;
                                        r_stage <= s_SAMPLE;
                                    else
                                        clockCounter := clockCounter + 1;
                                        r_stage <= s_WAIT_F;
                                    end if;
                            
                                when s_SAMPLE =>
                                    r_stage_dbg <= std_logic_vector(to_unsigned(4,4));
                                    --  sampling from the serial line that is now stable
                                    r_input_bits(bitIndex) <= r_serial_input;
                                    if (bitIndex=(packet_size-1)) then
                                        --  no more bits to sample
                                        bitIndex := 0;
                                        clockCounter := 0;
                                        r_new_data <= '1';
                                        r_stage <= s_DATA_WAIT;
                                    else
                                        --  need to sample again
                                        bitIndex := bitIndex + 1;
                                        clockCounter := 1;
                                        r_stage <= s_WAIT_F;
                                    end if;
                            
                                when s_DATA_WAIT =>
                                    r_stage_dbg <= std_logic_vector(to_unsigned(5,4));
                                    --  waiting for data acknowledgement
                                    if (r_data_ack='1') then
                                        --  data acknowledged
                                        r_new_data <= '0';
                                        r_stage <= s_DATA_ACK;
                                    else
                                        --  waiting for acknowledgement
                                        r_new_data <= '1';
                                        r_stage <= s_DATA_WAIT;
                                    end if;
                            
                                when s_DATA_ACK =>
                                    r_stage_dbg <= std_logic_vector(to_unsigned(6,4));
                                    if (r_data_ack='0') then
                                        --  going back
                                        r_stage <= s_IDLE;
                                    else
                                        --  waiting for de-assertion
                                        r_stage <= s_DATA_ACK;
                                    end if;
                                    
                            end case;
                        end if;
                    end if;
                end process UART_RX;

    --  assignments
    rx_data <= r_input_bits(8 downto 1);
    parity_chk <= s_pcheck;
    new_data <= r_new_data;
    stage_dbg <= r_stage_dbg;
    
    
end Behavioral;
