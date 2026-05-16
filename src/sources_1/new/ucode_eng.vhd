library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity ucode_eng is
    generic (
        addr_width: natural := 23;
        ucode_opcodes: string := "opcodedef.mem";
        ucode: string := "ucode.mem"
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  communication with cpu-core
        opcode: in std_logic_vector(7 downto 0);
        opA: in std_logic_vector(addr_width-1 downto 0);
        opB: in std_logic_vector(addr_width-1 downto 0);
        opC: in std_logic_vector(addr_width-1 downto 0);
        Nop: out std_logic_vector(1 downto 0);
        iword: out std_logic_vector(79 downto 0);
        --  sync signals
        cpu_strobe: in std_logic;
        uco_strobe: out std_logic
    );
end ucode_eng;

architecture Behavioral of ucode_eng is
    --  MICROCODE ENGINE
    --  loading the opcode configuration:
    --  this LUT contains rows of 16 bits which specify: the number of arguments (0,1,2 or 3), the addressing modes (2 blocks of 2 bits) + the number of micro-instructions that specify the instruction.
    --  how many microinstructions? i'd say at most 32? so an instruction could take up to 320 bytes to be defined...
    type opcode_details_type is array (0 to 256) of std_logic_vector(15 downto 0);
    impure function init_opcode_rom return opcode_details_type is 
      file text_file : text open read_mode is ucode_opcodes;
      variable text_line : line;
      variable ram_content : opcode_details_type;
      variable bv : bit_vector(ram_content(0)'range);
    begin
      for i in 0 to 255 loop
        readline(text_file, text_line);
        read(text_line, bv);
        ram_content(i) := to_stdlogicvector(bv);
      end loop;
      return ram_content;
    end function;
    signal opcode_def: opcode_details_type := init_opcode_rom;
    
    --  microcode
    type ucode_type is array (0 to 256) of std_logic_vector(79 downto 0);
    impure function init_ucode_rom return ucode_type is 
      file text_file : text open read_mode is ucode;
      variable text_line : line;
      variable ram_content : ucode_type;
      variable bv : bit_vector(ram_content(0)'range);
    begin
      for i in 0 to 255 loop
        readline(text_file, text_line);
        read(text_line, bv);
        ram_content(i) := to_stdlogicvector(bv);
      end loop;
      return ram_content;
    end function;
    signal ucode_def: ucode_type := init_ucode_rom;
    
    --  stages
    type t_SM is (s_INIT, s_IDLE, s0, s1, s2);
    signal r_stage: t_SM := s_INIT;
    
    --  samplers
    signal s_cpu_strobe: std_logic;
    
    --  outputs
    signal opcode_details: std_logic_vector(15 downto 0);
    signal r_uco_strobe: std_logic := '0';
    signal r_instr: std_logic_vector(79 downto 0);
    signal r_A: std_logic_vector(addr_width-1 downto 0);
    signal r_B: std_logic_vector(addr_width-1 downto 0);
    signal r_C: std_logic_vector(addr_width-1 downto 0);
begin
    --  assignments
    Nop <= opcode_details(15 downto 14);
    uco_strobe <= r_uco_strobe;
    iword <= r_instr;
    
    SAMPLER:    process(sysClk)
                begin
                    if (falling_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;


    MAIN:       process(sysClk)
                    variable addr: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                when s_INIT =>
                                    r_uco_strobe <= '0';
                                    r_instr <= (others=>'0');
                                    r_stage <= s_IDLE;
                                
                                when s_IDLE =>
                                    if (s_cpu_strobe='1') then
                                        --  incoming opcode, getting the details
                                        addr := to_integer(unsigned(opcode));
                                        opcode_details <= opcode_def(addr);
                                        r_stage <= s0;
                                    else
                                        --  waiting
                                        r_stage <= s_IDLE;                                        
                                    end if;
                                
                                when s0 =>
                                    --  need now to return
                                    if (s_cpu_strobe='0') then
                                        --  done
                                        r_uco_strobe <= '0';
                                        --  checking if we have arguments
                                        if (opcode_details(15 downto 14)="00") then
                                            --  no args
                                            r_stage <= s2;
                                        else
                                            --  presence of args, must ask the cpu to retrieve them from the sram
                                            r_stage <= s1;
                                        end if;
                                    else
                                        --  waiting
                                        r_uco_strobe <= '1';
                                        r_stage <= s0;
                                    end if;
                            
                                when s1 =>
                                    --  now waiting for the cpu to send back the operand it has read so that we may begin building the 80 bit words
                                    if (s_cpu_strobe='1') then
                                        --  operands from the cpu
                                        r_A <= opA;
                                        r_B <= opB;
                                        r_C <= opC;
                                        
                                    else
                                        --  waiting
                                        r_stage <= s1;
                                    end if;
                            end case;
                        end if;
                    end if;
                end process MAIN;

end Behavioral;
