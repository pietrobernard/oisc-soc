library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity subdev_CPU_ucode_core is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  hardware id for the UART
        --  this allows for data-packets sent from the uart device to reach this and not other sub-devs of the uart
        hw_id: integer := 0;
        hw_i2c_addr: std_logic_vector(6 downto 0) := std_logic_vector(to_unsigned(80, 7));
        --  device manager setup
        dev_id: integer := 1;
        local_mem_begin: integer := 0;      --  start of memory space
        local_mem_nvrt: integer := 0;       --  number of virtual registers
        sram_mem_begin: integer := 0;       --  start of sram range (lies outside of the local memory range defined above)
        sram_mem_end: integer := 0;         --  end of sram range
        regcfg: string := "cpu_registers.mem";    --  logical registers configuration file
        n_irq_lines: natural := 8;
        --  settings
        reset_vector: natural := 0;
        --  microcode definitions
        ucode_opcodes: string := "opcodedef.mem";
        ucode: string := "ucode.mem"
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  sub-system signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;         --  this line will go high if the system bus has been granted
        --  hardware lines
        irq_lines: in std_logic_vector(n_irq_lines-1 downto 0);
        irq_grant: out std_logic_vector(n_irq_lines-1 downto 0)
    );
end subdev_CPU_ucode_core;

architecture Behavioral of subdev_CPU_ucode_core is
    --  subdev interface
    signal r_bus_in_cmd: std_logic := '0';
    signal r_bus_in_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_bus_in_data: std_logic_vector(data_width-1 downto 0) := (others=>'0');
    signal r_bus_in_keep: std_logic := '0';
    signal r_bus_in_latch: std_logic := '0';
    
    --  sampling sub-bus
    signal s_bus_out_cmd: std_logic;
    signal s_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal s_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal s_bus_out_drdy: std_logic;
    signal s_bus_out_done: std_logic;
    signal s_bus_err: std_logic;
    signal s_bus_chg: std_logic;
    signal ss_bus_out_cmd: std_logic := '0';        
    signal ss_bus_out_drdy: std_logic := '0';
    signal ss_bus_out_done: std_logic := '0';
    signal ss_bus_err: std_logic := '0';
    signal ss_bus_chg: std_logic := '0';
    
    --  cpu state machine
    type t_SM is (
                    s_INIT,
                    --  operand fetch stages
                    s_OPF_0, s_OPF_1, s_OPF_2, s_OPF_3,
                    --  operand arguments fetch stages
                    s_OPA_0, s_OPA_1, s_OPA_2,
                    --  decoding
                    s_DEC_0, s_DEC_1, s_DEC_2, s_DEC_3
                 );
    signal r_stage: t_SM := s_INIT;
    
    --  register file controls
    signal r_reg_cmd: std_logic;
    signal r_reg_addr: std_logic_vector(7 downto 0);
    signal r_reg_data_to: std_logic_vector(7 downto 0);
    signal s_reg_data_fr: std_logic_vector(7 downto 0);
    signal r_reg_latch: std_logic;
    signal s_reg_drdy: std_logic;
    signal s_reg_done: std_logic;
    
    --  sampling signals
    signal ss_reg_drdy: std_logic;
    signal ss_reg_done: std_logic;
    
    --  full adder
    signal s_fadd_sum: std_logic_vector(31 downto 0);
    signal s_fadd_ovf: std_logic;
    signal s_fadd_zf: std_logic;
    signal s_fadd_pf: std_logic;
    signal s_fadd_sf: std_logic;
    
    --  special registers
    signal r_pc: natural := 0;
    signal r_instr_opcode: std_logic_vector(7 downto 0);
    signal r_instr_details: std_logic_vector(15 downto 0);
    signal r_instr_args: std_logic_vector(71 downto 0);
    
    
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
    
begin
    --  subbus to interface with the central system
    SBUSINT:    entity work.subbus_dev(Behavioral)
                generic map (
                    dev_id => dev_id,
                    local_mem_begin => local_mem_begin,
                    local_mem_nvrt => local_mem_nvrt
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  system bus interface signals
                    bus_lines => bus_lines,
                    bus_strobe_M => bus_strobe_M,
                    bus_strobe_S => bus_strobe_S,
                    bus_keep => bus_keep,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  addendum for the sub-dev
                    bus_req_sys => bus_req_sys,
                    bus_rdy_sys => bus_rdy_sys,
                    --  interface signals
                    dev_in_cmd => r_bus_in_cmd,
                    dev_in_addr => r_bus_in_addr,
                    dev_in_data => r_bus_in_data,
                    dev_in_keep => r_bus_in_keep,
                    dev_in_latch => r_bus_in_latch,
                    dev_out_cmd => s_bus_out_cmd,   --  output command
                    dev_out_addr => s_bus_out_addr, --  output address
                    dev_out_data => s_bus_out_data, --  output data
                    dev_out_drdy => s_bus_out_drdy, --  when new data arrives
                    dev_out_done => s_bus_out_done, --  when no more transactions
                    dev_err => s_bus_err,           --  if an error occurrs
                    dev_chg => s_bus_chg            --  when an operation on local physical registers completes
                );
            
    --  register file
    --  the cpu has 24 general purpose registers. These are 8, 16 and 32 bit wide
    --  these use the 32 base registers in different combinations. Basically AX and EAX are extensions of A
    --  A is an 8 bit register, AX is extended to 16 bit (meaning that the lower 8 bits are still the ones of A)
    --  finally EAX is a 32 bit register where the lower 2 registers are the 16 bits of AX and the upper 16 are new.
    --  A,AX,EAX | B,BX,EBX | C,CX,ECX | D,DX,EDX | E,EX,EEX | F,FX,EFX | G,GX,EGX | H,HX,EHX
    REGFILE:    entity work.regs(Behavioral) generic map (
                    memfile => regcfg,
                    n_logical => 24
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  register interface
                    r_cmd => r_reg_cmd,
                    r_address => r_reg_addr,
                    r_data_to => r_reg_data_to,
                    r_data_fr => s_reg_data_fr,
                    latch_cmd => r_reg_latch,
                    drdy => s_reg_drdy,
                    done => s_reg_done
                );
    
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
                    --  counters
                    variable c: natural := 0;
                    variable d: natural := 0;
                    --  placeholders
                    variable am: std_logic_vector(1 downto 0) := "00";  --  00 : immediate, 01 : direct, 10 : indirect
                    variable ds: natural := 0;                          --  data size in bytes (1,2 or 4)
                    variable addr: natural := 0;                        --  placeholder for address
                    variable special_reg: std_logic_vector(2 downto 0) := "000";
                    --  number of arguments
                    variable Nargs: natural := 0;
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                --  cpu initialization
                                when s_INIT =>
                                    --  system bus controls
                                    r_bus_in_cmd <= '0';
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_addr <= (others=>'0');
                                    r_bus_in_keep <= '0';
                                    r_bus_in_latch <= '0';
                                    --  general purpose registers controls
                                    r_reg_cmd <= '0';
                                    r_reg_addr <= (others=>'0');
                                    r_reg_data_to <= (others=>'0');
                                    r_reg_latch <= '0';
                                    --  preparing counters
                                    c := 0;
                                    d := 0;
                                    r_stage <= s_OPF_0;
                                
                                ---------------------------------------------------------------------------
                                --
                                --  OPCODE FETCH
                                --
                                when s_OPF_0 =>
                                    r_bus_in_cmd <= '1';
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_addr <= std_logic_vector(to_unsigned(r_pc, addr_width));
                                    r_bus_in_keep <= '0';
                                    r_stage <= s_OPF_1;
                                
                                when s_OPF_1 =>
                                    if (ss_bus_out_drdy='1') then
                                        r_instr_opcode <= s_bus_out_data;
                                        r_stage <= s_OPF_2;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_OPF_1;
                                    end if;
                            
                                when s_OPF_2 =>
                                    if (ss_bus_out_drdy='0') then
                                        --  bus has been released, so now we can get the details
                                        r_instr_details <= opcode_def(to_integer(unsigned(r_instr_opcode)));
                                        r_stage <= s_OPF_3;
                                    else
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_OPF_2;
                                    end if;
                                
                                when s_OPF_3 =>
                                    --  now we see what we have
                                    Nargs := to_integer(unsigned(r_instr_details(15 downto 14)))*3;
                                    r_pc <= r_pc + 1;
                                    if (Nargs=0) then
                                        --  no arguments to fetch, jumping to decode
                                        r_stage <= s_DEC_0;
                                    else
                                        --  must fetch args
                                        c := 0;
                                        r_stage <= s_OPA_0;
                                    end if;
                                    
                                ---------------------------------------------------------------------------
                                --
                                --  ARGUMENT FETCH from the SRAM
                                --
                                when s_OPA_0 =>
                                    r_bus_in_cmd <= '1';
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_addr <= std_logic_vector(to_unsigned(r_pc, addr_width));
                                    if (c=(Nargs-1)) then
                                        r_bus_in_keep <= '0';
                                    else
                                        r_bus_in_keep <= '1';
                                    end if;
                                    r_stage <= s_OPA_1;
                                
                                when s_OPA_1 =>
                                    if (ss_bus_out_drdy='1') then
                                        --  got the argument
                                        r_instr_args(((c+1)*8)-1 downto c*8) <= s_bus_out_data;
                                        r_stage <= s_OPA_2;
                                    else
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_OPA_1;
                                    end if;
                                
                                when s_OPA_2 =>
                                    if (ss_bus_out_drdy='0') then
                                        r_pc <= r_pc + 1;
                                        if (c=(Nargs-1)) then
                                            --  finished, jumping to decode
                                            c := 0;
                                            r_stage <= s_DEC_0;
                                        else
                                            --  more to fetch
                                            c := c + 1;
                                            r_stage <= s_OPA_0;
                                        end if;
                                    else
                                        --  releasing
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_OPA_2;
                                    end if;
                            
                                ---------------------------------------------------------------------------
                                --  
                                --  After having got the number of specified arguments, we have to start
                                --  building the 80 bit subleq instruction words.
                                --  now, here we have:
                                --  first 2 bits that define how many arguments, then we have the following 6
                                --  bits that instead tell how to arrange the arguments:
                                --  AA_BB_CC
                                --  AA = 0,1,2 or 3 : index of the fetched argument that will be the A operand
                                --  BB = index of the fetched argument that will be the B operand (can be the same as A)
                                --  CC = index of the fetch argument that will be the C operand
                                --  for instance the clear instruction to clear a register will have only 1 argument
                                --  AA_BB_CC -> 01_01_00
                                --  the 00 means "not present". If the C is not present, then in case of a jump condition,
                                --  the pc will jump to +1.
                                --  then in the microcode, the addressing mode of each operand will be specified and so
                                --  the 80 bit word can be built.
                                --
                                when s_DEC_0 =>
                                    --  now the microcode
                                    
                                
                                
                            end case;
                        end if;
                    end if;
                end process MAIN;

end Behavioral;
