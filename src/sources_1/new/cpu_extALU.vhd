library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  the extended logical module adds some common logical and bit manipulation functions
--  in the same way as the x86 math co-processor added functionalities, albeit here in a much more
--  simplified way. The cpu core just addresses this device as a separate entity, so the core remains
--  a OISC core with just the subleq instruction and nothing more.
entity cpu_extALU is
    generic (
        addr_width: natural := 23
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  same interface as the registers, so
        cmd: in std_logic;
        address: in std_logic_vector(3 downto 0);
        data_in: in std_logic_vector(31 downto 0);
        data_out: out std_logic_vector(31 downto 0);
        latch_cmd: in std_logic;
        drdy: out std_logic;
        done: out std_logic
    );
end cpu_extALU;

architecture Behavioral of cpu_extALU is
    --  control
    signal r_data_out: std_logic_vector(31 downto 0);
    signal r_done: std_logic;
    signal r_drdy: std_logic;
    --  sampler
    signal ss_latch: std_logic;
    signal ss_addr: std_logic_vector(3 downto 0);
    signal ss_operand: std_logic_vector(31 downto 0);
    signal ss_cmd: std_logic;
    --  registers
    signal r_opA: std_logic_vector(31 downto 0);
    signal r_opB: std_logic_vector(31 downto 0);
    signal r_iop: natural;
    --  state machine
    type t_SM is (s_INIT, s_IDLE, s_W_0, s_W_1, s_R_0, s_R_1);
    signal r_stage: t_SM := s_IDLE;
    
    --  results
    signal s_A_and_B: std_logic_vector(31 downto 0);
    signal s_A_or_B: std_logic_vector(31 downto 0);
    signal s_A_xor_B: std_logic_vector(31 downto 0);
    signal s_L_shift: std_logic_vector(31 downto 0);
    signal s_R_shift: std_logic_vector(31 downto 0);
    signal s_L_rotate: std_logic_vector(31 downto 0);
    signal s_R_rotate: std_logic_vector(31 downto 0);
    
    --  sync
    signal ss_sync_0: std_logic := '0';
begin

    AND_UNIT:   entity work.and_port_nbits(Behavioral)
                    generic map (
                        nbits => 32
                    ) port map (
                        operandA => r_opA,
                        operandB => r_opB,
                        result => s_A_and_B
                    );
    
    OR_UNIT:    entity work.or_port_nbits(Behavioral)
                    generic map (
                        nbits => 32
                    ) port map (
                        operandA => r_opA,
                        operandB => r_opB,
                        result => s_A_or_B
                    );

    XOR_UNIT:   entity work.xor_port_nbits(Behavioral)
                    generic map (
                        nbits => 32
                    ) port map (
                        operandA => r_opA,
                        operandB => r_opB,
                        result => s_A_xor_B
                    );
    
    SHIFT_UNIT: entity work.shift_unit_nbits(Behavioral)
                    generic map (
                        nbits => 32
                    ) port map (
                        operand => r_opA,
                        amount => r_iop,
                        result_L => s_L_shift,
                        result_R => s_R_shift
                    );
    
    ROTATE_UNIT:entity work.rotate_unit_nbits(Behavioral)
                    generic map (
                        nbits => 32
                    ) port map (
                        operand => r_opA,
                        amount => r_iop,
                        result_L => s_L_rotate,
                        result_R => s_R_rotate
                    );

    SAMP:   process(sysClk)
            begin
                if (rising_edge(sysClk)) then
                    case (r_stage) is
                        when s_INIT =>
                            ss_sync_0 <= '0';
                        
                        when s_IDLE =>
                            ss_latch <= latch_cmd;
                            ss_addr <= address;
                            ss_operand <= data_in;
                            ss_cmd <= cmd;
                            ss_sync_0 <= '1';
                        
                        when s_R_0 =>
                            ss_sync_0 <= '0';
                        
                        when s_W_0 =>
                            ss_sync_0 <= '0';
                        
                        when s_W_1 =>
                            ss_latch <= latch_cmd;
                        
                        when s_R_1 =>
                            ss_latch <= latch_cmd;
                        
                        when others =>
                            null;
                    end case;                   
                end if;
            end process SAMP;
          
    MAIN:   process(sysClk)
                variable i_op: natural := 0;
            begin
                if (rising_edge(sysClk)) then
                    if (sysRstb='0') then
                        r_stage <= s_INIT;
                    else
                        case (r_stage) is
                            when s_INIT =>
                                r_drdy <= '0';
                                r_done <= '0';
                                r_data_out <= (others=>'0');
                                r_opA <= (others=>'0');
                                r_opB <= (others=>'0');
                                r_stage <= s_IDLE;
                            
                            when s_IDLE =>
                                if ((ss_sync_0='1') and (ss_latch='1')) then
                                    --  now we can go
                                    if (ss_cmd='0') then
                                        r_stage <= s_W_0;
                                    else
                                        r_stage <= s_R_0;
                                    end if;
                                else
                                    r_stage <= s_IDLE;
                                end if;
                            
                            when s_W_0 =>
                                --  qui per scrivere
                                case (ss_addr) is
                                    when "1000" =>
                                        --  l'indirizzo 0 viene usato per lo storage di operando A
                                        r_opA <= ss_operand;
                                        r_stage <= s_W_1;
                                    
                                    when "1001" =>
                                        --  l'indirizzo 1 viene usato per lo storage di operando B
                                        r_opB <= ss_operand;
                                        r_iop <= to_integer(unsigned(ss_operand));
                                        r_stage <= s_W_1;
                                    
                                    when others =>
                                        --  writing to other registers does nothing
                                        r_stage <= s_W_1;
                                end case;
                            
                            when s_W_1 =>
                                if (ss_latch='0') then
                                    r_drdy <= '0';
                                    r_done <= '0';
                                    r_stage <= s_IDLE;
                                else
                                    r_drdy <= '1';
                                    r_done <= '1';
                                    r_stage <= s_W_1;
                                end if;
                            
                            when s_R_0 =>
                                --  errore: i_op deve andare da opB
                                i_op := to_integer(unsigned(r_opB));
                                case (ss_addr) is
                                    when "0000" =>
                                        r_data_out <= s_A_and_B;
                                        
                                    when "0001" =>
                                        r_data_out <= s_A_or_B;
                                        
                                    when "0010" =>
                                        r_data_out <= s_A_xor_B;
                                                                                                                
                                    when "0011" =>
                                        --  must shift opA to the left by 'i_op' zeros, so
                                        r_data_out <= s_L_shift;
                                    
                                    when "0100" =>
                                        --  must shift opA to the right by 'i_op' zeros, so
                                        r_data_out <= s_R_shift;
                                    
                                    when "0101" =>
                                        --  must rotate bit right by the i_op quantity    
                                        r_data_out <= s_L_rotate;
                                    
                                    when "0110" =>
                                        r_data_out <= s_R_rotate;
                                    
                                    when others =>
                                        --  reading from any other register returns 0
                                        r_data_out <= (others=>'0');
                                end case;
                                r_stage <= s_R_1;
                            
                            when s_R_1 =>
                                if (ss_latch='0') then
                                    r_drdy <= '0';
                                    r_done <= '0';
                                    r_stage <= s_IDLE;
                                else
                                    r_drdy <= '1';
                                    r_done <= '1';
                                    r_stage <= s_R_1;
                                end if;
                            
                            when others =>
                                r_stage <= s_IDLE;
                        end case;
                    end if;
                end if;
            end process MAIN;

    --  assignment
    data_out <= r_data_out;
    drdy <= r_drdy;
    done <= r_done;
end Behavioral;
