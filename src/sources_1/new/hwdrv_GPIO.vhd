library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity hwdrv_GPIO is
    generic (
        data_width: natural := 8;
        port_type: natural := 0     --  0 : unidir, 1 : bidir
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  output databus lanes
        data_out: out std_logic_vector(data_width-1 downto 0);
        data_drdy: out std_logic;
        data_ack: in std_logic;
        --  input databus lanes
        data_in: in std_logic_vector(data_width-1 downto 0);
        data_latch: in std_logic;
        data_done: out std_logic;
        --  hardware lines
        extport: inout std_logic_vector(data_width-1 downto 0);
        drdy: in std_logic;
        dack: out std_logic        
    );
end hwdrv_GPIO;

architecture Behavioral of hwdrv_GPIO is
    --  hardware drivers
    signal r_dack: std_logic := '0';
    signal s_drdy: std_logic;
    signal r_data_to: std_logic_vector(data_width-1 downto 0);
    signal s_data_from: std_logic_vector(data_width-1 downto 0);
    signal r_dirs: std_logic_vector(data_width-1 downto 0);
    
    --  state machine
    type t_SM is (s_INIT, s_IDLE_0, s_IDLE_1, s_EXT_0, s_EXT_1, s_EXT_2, s_EXT_3, s_INT_0, s_INT_1, s_INT_2, s_INT_3, s_EXTd_0, s_EXTd_1, s_EXTd_2, s_EXTd_3, s_EXTd_4, s_INTd_0, s_INTd_1);
    signal r_stage: t_SM := s_INIT;
    
    --  sampling
    signal ss_drdy: std_logic;
    signal ss_data_latch: std_logic;
    signal ss_data_ack: std_logic;
    signal ss_from_strobe_S: std_logic;
    
    --  signals to drive the interface
    signal r_data_out: std_logic_vector(data_width-1 downto 0);
    signal r_data_drdy: std_logic;
    signal r_data_done: std_logic;
    
    --  const
    constant strobe_M_pin: natural := 4;
    constant strobe_S_pin: natural := 5;
    constant keep_M_pin: natural := 6;
    constant keep_S_pin: natural := 7;
    constant dirs_bidir: std_logic_vector(3 downto 0) := "0101";
begin
    --  hardware drivers
    dack <= r_dack;
    
    --  mi creo 8 drivers
    GENFOR_PORTDRVS: for i in 0 to 7 generate
        PORT_DRIVER_i:  entity work.inout_port(Behavioral) generic map (nbits => 1) port map (io(0) => extport(i), data_to(0) => r_data_to(i), data_from(0) => s_data_from(i), dir => r_dirs(i));
    end generate GENFOR_PORTDRVS;
        
    --  hardware bus drivers
    data_out <= r_data_out;
    data_drdy <= r_data_drdy;
    data_done <= r_data_done;

    SAMPLER:    process(sysClk)
                begin
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;

    MAIN:   process(sysClk)
                variable cond: std_logic_vector(1 downto 0) := "00";
                variable c: natural := 0;
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>
                                r_dack <= '0';
                                r_data_to <= (others=>'0');
                                r_data_out <= (others=>'0');
                                r_data_drdy <= '0';
                                r_data_done <= '0';
                                if (port_type=0) then
                                    r_dirs <= (others=>'0');
                                    r_stage <= s_IDLE_0;
                                else
                                    r_dirs(7 downto 4) <= dirs_bidir;
                                    r_dirs(3 downto 0) <= (others=>'0');
                                    r_stage <= s_IDLE_1;
                                end if;
                            
                            --  BIDIRECTIONAL PORT
                            when s_IDLE_1 =>
                                cond := (ss_data_latch & ss_from_strobe_S);
                                case (cond) is
                                    when "01" =>
                                        --  the attached device is sending data
                                        r_dirs(7 downto 4) <= dirs_bidir;
                                        c := 0;
                                        r_data_to(strobe_M_pin) <= '0';
                                        r_stage <= s_EXTd_0;
                                    
                                    when "10" =>
                                        --  we have to send data to the device
                                        c := 0;
                                        r_data_to(strobe_M_pin) <= '1';
                                        r_stage <= s_INTd_0;
                                    
                                    when "11" =>
                                        --  concurrency : first we need to clear the device
                                        null;
                                    
                                    when "00" =>
                                        --  idling
                                        r_data_to(strobe_M_pin) <= '0';
                                        r_stage <= s_IDLE_1;
                                    
                                end case;
                            
                            when s_INTd_0 =>
                                --  
                            
                            when s_EXTd_0 =>
                                --  device is sending data, reading two nibbles of 4 bits each
                                if (c=0) then
                                    r_data_out(3 downto 0) <= s_data_from(7 downto 4);
                                    r_data_done <= '0';
                                else
                                    r_data_out(7 downto 4) <= s_data_from(7 downto 4);
                                    r_data_done <= '1';
                                end if;
                                r_stage <= s_EXTd_1;
                            
                            when s_EXTd_1 =>
                                --  signalling the device we've read
                                if (ss_from_strobe_S='0') then
                                    r_data_to(strobe_M_pin) <= '0';
                                    r_stage <= s_EXTd_2;
                                else
                                    r_data_to(strobe_M_pin) <= '1';
                                    r_stage <= s_EXTd_1;
                                end if;
                                
                            when s_EXTd_2 =>
                                --  sending the data to the handler
                                if (ss_data_ack='1') then
                                    r_data_drdy <= '0';
                                    r_data_done <= '0';
                                    r_stage <= s_EXTd_3;
                                else
                                    r_data_drdy <= '1';
                                    r_stage <= s_EXTd_2;
                                end if;
                            
                            when s_EXTd_3 =>
                                if (ss_data_ack='0') then
                                    if (c=0) then
                                        c := 1;
                                        r_stage <= s_EXTd_4;
                                    else
                                        c := 0;
                                        r_stage <= s_IDLE_1;
                                    end if;
                                else
                                    r_stage <= s_EXTd_3;
                                end if;
                            
                            when s_EXTd_4 =>
                                if (ss_from_strobe_S='1') then
                                    r_stage <= s_EXTd_0;
                                else
                                    r_stage <= s_EXTd_4;
                                end if;
                            
                            --  UNIDIRECTIONAL PORT
                            when s_IDLE_0 =>
                                --  waiting for an event by the port or for a command to write to the port
                                cond := (ss_data_latch & ss_drdy);
                                case (cond) is
                                    when "01" =>
                                        --  event from the port
                                        r_dirs <= (others=>'0');
                                        r_stage <= s_EXT_0;
                                    
                                    when "10" =>
                                        --  event from the system towards the port
                                        r_dirs <= (others=>'1');
                                        r_stage <= s_INT_0;
                                    
                                    when others =>
                                        --  idling.
                                        --  concurrency is not allowed here since the port is unidirectional
                                        r_stage <= s_IDLE_0;
                                end case;
                        
                            when s_EXT_0 =>
                                r_data_out <= s_data_from;
                                r_stage <= s_EXT_1;
                        
                            when s_EXT_1 =>
                                --  unidirectional
                                if (ss_drdy='0') then
                                    r_dack <= '0';
                                    r_stage <= s_EXT_2;
                                else
                                    r_dack <= '1';
                                    r_stage <= s_EXT_1;
                                end if;
                            
                            when s_EXT_2 =>
                                --  now to send the read data to the handler
                                if (ss_data_ack='1') then
                                    r_data_drdy <= '0';
                                    r_data_done <= '0';
                                    r_stage <= s_EXT_3;
                                else
                                    --  waiting
                                    r_data_drdy <= '1';
                                    r_data_done <= '1';
                                    r_stage <= s_EXT_2;
                                end if;
                        
                            when s_EXT_3 =>
                                if (ss_data_ack='0') then
                                    r_stage <= s_IDLE_0;
                                else
                                    r_stage <= s_EXT_3;
                                end if;
                        
                            when s_INT_0 =>
                                r_data_to <= data_in;
                                r_stage <= s_INT_1;
                            
                            when s_INT_1 =>
                                --  unidirectional write
                                if (ss_drdy='1') then
                                    r_dack <= '0';
                                    r_stage <= s_INT_2;
                                else
                                    r_dack <= '1';
                                    r_stage <= s_INT_1;
                                end if;
                            
                            when s_INT_2 =>
                                if (ss_drdy='0') then
                                    --  ora siamo pronti per rispondere
                                    r_stage <= s_INT_3;
                                else
                                    r_stage <= s_INT_2;
                                end if;
                            
                            when s_INT_3 =>
                                if (ss_data_latch='0') then
                                    r_data_drdy <= '0';
                                    r_data_done <= '0';
                                    r_stage <= s_IDLE_0;
                                else
                                    r_data_drdy <= '1';
                                    r_data_done <= '1';
                                    r_stage <= s_INT_3;
                                end if;
                        end case;
                    end if;
                end if;
            end process MAIN;
end Behavioral;
