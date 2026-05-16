library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;

entity subdev_CPU_core_v2 is
    generic (
        --  bus topology
        bus_width: integer := 32;
        data_width: integer := 8;
        addr_width: integer := 23;
        --  hardware id for the UART
        --  this allows for data-packets sent from the uart device to reach this and not other sub-devs of the uart
        hw_id: integer := 0;
        --  device manager setup
        dev_id: integer := 1;
        local_mem_begin: integer := 0;          --  start of memory space
        local_mem_nvrt: integer := 0;           --  number of virtual registers
        sram_mem_begin: integer := 0;           --  start of sram range (lies outside of the local memory range defined above)
        sram_mem_end: integer := 0;             --  end of sram range
        regcfg: string := "cpu_registers.mem";  --  logical registers configuration file
        --  settings
        reset_vector: natural := 0
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  sub-system signals
        bus_lines: inout std_logic_vector(bus_width-1 downto 0);
        bus_strobe_M: inout std_logic;
        bus_strobe_S: inout std_logic;
        bus_keep: inout std_logic;
        bus_done_S: inout std_logic;
        bus_rq: out std_logic;
        bus_grant: in std_logic;
        bus_busy: in std_logic;
        --  booking signals
        bus_req_sys: out std_logic;         --  this line must be driven high if one of the peripherals wants to acquire the mainbus
        bus_rdy_sys: in std_logic;         --  this line will go high if the system bus has been granted
        bus_err_sys: in std_logic;
        --  core controls
        run: in std_logic;
        reset: in std_logic;
        halt: out std_logic;
        --  mini bus to exchange interrupt vectors with the interrupt controller
        irq_vector_bus: in std_logic_vector(31 downto 0);
        irq_vector_drdy: in std_logic;
        irq_vector_done: in std_logic;
        irq_vector_ack: out std_logic;
        --  synchro
        irq_active: out std_logic;
        irq_active_wait: in std_logic;
        irq_prepare: in std_logic;
        --  debug
        dbg_instr: out natural;
        dbg_cpu_subbus_dev: out natural;
        dbg_cpu_subbus_dev_int: out natural;
        output_port: out natural
    );
end subdev_CPU_core_v2;

architecture Behavioral of subdev_CPU_core_v2 is
    --  some constants
    constant cpu_private_begin: natural := local_mem_begin + 64;
    constant cpu_private_end: natural := local_mem_begin + 63 + local_mem_nvrt;    
    
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
    signal ss_bus_out_data: std_logic_vector(data_width-1 downto 0);
    signal ss_bus_out_addr: std_logic_vector(addr_width-1 downto 0);
    signal ss_bus_err: std_logic := '0';
    signal ss_bus_chg: std_logic := '0';
    
    --  cpu state machine
    type t_SM is (s_INIT, s_STAT, s_IF_0, s_IF_1, s_IF_2, s_OF_0, s_OF_BUS_0, s_OF_BUS_1, s_OF_BUS_2, s_OF_SREG_0, s_OF_GPREG_0, s_OF_GPREG_1, s_OF_GPREG_2, s_OF_GPREG_3, s_OF_GPREG_4,
    s_OF_IN_0, s_OF_IN_1, s_CHK_A, s_CHK_B, s_CHK_C, s_FETCH_A, s_FETCH_B, s_FETCH_C, s_OF_COMMON,
    s_EXEC_0, s_EXEC_1, s_EXEC_2, s_WBACK_SREG_0, s_WBACK_GPREG_0, s_WBACK_GPREG_1, s_WBACK_GPREG_2, s_WBACK_GPREG_3, s_WBACK_GPREG_4, s_WBACK_BUS_0, s_WBACK_BUS_1, s_WBACK_BUS_2,
    s_WBACK_IN_SREG_0, s_WBACK_IN_PRE, s_WBACK_IN_GPREG_0, s_WBACK_IN_GPREG_1, s_WBACK_IN_GPREG_2, s_WBACK_IN_BUS_0, s_WBACK_IN_BUS_1, s_WBACK_IN_BUS_2,
    s_JMP, s_IRH_PRE, s_IRH_0, s_IRH_1, s_IRH_2, s_IRH_3, s_IRC, s_HLT, s_ERR);
    signal r_stage: t_SM := s_INIT;
    signal r_jump_0: t_SM := s_INIT;
    signal r_jump_1: t_SM := s_INIT;
            
    --  CPU registers (other than the general purpose ones)
    signal r_acc: std_logic_vector(31 downto 0);
    signal r_tmp_1: std_logic_vector(31 downto 0);
    signal r_tmp_2: std_logic_vector(31 downto 0);
    signal r_flag_stat: std_logic_vector(7 downto 0);
    signal r_pc: natural := 0;
    signal r_pc_back: natural := 0;
    signal r_sp: natural := 0;
    signal r_aluB_data: std_logic_vector(31 downto 0);
    signal r_alu_ds: natural := 0;
    signal r_opC_jump: std_logic_vector(addr_width downto 0);   --  this intentionally has 24 bits instead of 23 since bit 24 stores the addressing mode of this operand
    
    --  helper / non addressable registers
    signal r_instr_word: std_logic_vector(79 downto 0);     --  instruction word : holds the 80 bit that define a SUBLEQ instruction
    signal r_opA_addr: std_logic_vector(addr_width downto 0);   --  these have 24 bits instead of 23 because it's easier to manage
    signal r_opB_addr: std_logic_vector(addr_width downto 0);   --  these have 24 bits instead of 23 because it's easier to manage
    signal r_opA_data: std_logic_vector(31 downto 0);       --  opA_data : ALU input register A
    signal r_opB_data: std_logic_vector(31 downto 0);       --  opB_data : ALU input register B
    
    --  auxiliary
    signal r_op_addr: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
    signal r_op_data: std_logic_vector(31 downto 0) := (others=>'0');
    signal r_pvt: std_logic_vector(2 downto 0) := "000";
            
    --  register file controls (8, 16 and 32 bits extendable)
    signal r_reg_cmd: std_logic;
    signal r_reg_addr: std_logic_vector(7 downto 0);
    signal r_reg_data_to: std_logic_vector(7 downto 0);
    signal s_reg_data_fr: std_logic_vector(7 downto 0);
    signal ss_reg_data_fr: std_logic_vector(7 downto 0);
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
    
    --  extended logic module
    signal r_xlm_cmd: std_logic := '0';
    signal r_xlm_addr: std_logic_vector(3 downto 0) := (others=>'0');
    signal r_xlm_data_in: std_logic_vector(31 downto 0) := (others=>'0');
    signal r_xlm_latch: std_logic := '0';
    signal s_xlm_data_out: std_logic_vector(31 downto 0);
    signal ss_xlm_data_out: std_logic_vector(31 downto 0);
    signal s_xlm_drdy: std_logic;
    signal s_xlm_done: std_logic;
    
    --  sampling
    signal ss_xlm_drdy: std_logic;
    
    --  cpu control signals
    signal ss_run: std_logic;
    signal ss_reset: std_logic;
    
    --  context switch saving things
    signal r_pc_save: natural := 0;
    signal r_flag_stat_save: std_logic_vector(7 downto 0) := (others=>'0');
    
    --  interrupt registers
    type isr_data is array (0 to 7) of std_logic_vector(31 downto 0);
    signal isr_file: isr_data;
    
    --  interrupt related quantities
    signal r_irq_vector_ack: std_logic := '0';
    signal r_irq_active: std_logic := '0';
    
    --  sampling interrupt
    signal ss_irq_vector_drdy: std_logic := '0';
    signal ss_irq_vector_done: std_logic := '0';
    signal ss_irq_vector_bus: std_logic_vector(31 downto 0) := (others=>'0');
    signal ss_irq_active_wait: std_logic := '0';
    signal ss_irq_prepare: std_logic := '0';
    
    --  debug
    signal r_dbg_instr: natural := 0;
    signal s_bus_mode: std_logic_vector(1 downto 0);
    signal ss_bus_mode: std_logic_vector(1 downto 0);
    
    --  synchro
    signal ss_sync_0: std_logic := '0';
    
    --  halt flag
    signal r_HLT: std_logic := '0';
begin
    --  subbus to interface with the central system
    SBUSINT:    entity work.subbus_dev_v2(Behavioral)
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
                    bus_done_S => bus_done_S,
                    bus_rq => bus_rq,
                    bus_grant => bus_grant,
                    bus_busy => bus_busy,
                    --  addendum for the sub-dev
                    bus_req_sys => bus_req_sys,
                    bus_rdy_sys => bus_rdy_sys,
                    bus_err_sys => bus_err_sys,
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
                    dev_chg => s_bus_chg,           --  when an operation on local physical registers completes
                    --  debug
                    dbg_stage => dbg_cpu_subbus_dev,
                    dbg_trx_stage => dbg_cpu_subbus_dev_int,
                    dbg_bus_mode => s_bus_mode
                );
    
            
    --  register file
    --  the cpu has 24 general purpose registers. These are 8, 16 and 32 bit wide
    --  these use the 32 base registers in different combinations. Basically AX and EAX are extensions of A
    --  A is an 8 bit register, AX is extended to 16 bit (meaning that the lower 8 bits are still the ones of A)
    --  finally EAX is a 32 bit register where the lower 2 registers are the 16 bits of AX and the upper 16 are new.
    --  A,AX,EAX | B,BX,EBX | C,CX,ECX | D,DX,EDX | E,EX,EEX | F,FX,EFX | G,GX,EGX | H,HX,EHX
    REGFILE:    entity work.regs(Behavioral) generic map (
                    memfile => "cpu_registers.mem",
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
    
    --  Extended Logical Module : this acts as a separate device that can be addressed by the CPU in order to perform
    --  certain logical manipulation operations (like the co-processor for the x86 family)
    XLMDEV:     entity work.cpu_extALU(Behavioral) generic map (
                    addr_width => addr_width
                ) port map (
                    sysClk => sysClk,
                    sysRstb => sysRstb,
                    --  interface
                    cmd => r_xlm_cmd,
                    address => r_xlm_addr,
                    data_in => r_xlm_data_in,
                    data_out => s_xlm_data_out,
                    latch_cmd => r_xlm_latch,
                    drdy => s_xlm_drdy,
                    done => s_xlm_done
                );
    
    --  full adder in CA2 to perform the subleq operation
    FADDER:     entity work.full_adder_CA2_Nbits(Behavioral) generic map (
                    Nbits => 32
                ) port map (
                    a => r_opA_data,
                    b => r_aluB_data,
                    ds => r_alu_ds,
                    s => s_fadd_sum,
                    ovf => s_fadd_ovf,
                    zf => s_fadd_zf,
                    pf => s_fadd_pf,
                    sf => s_fadd_sf
                );
    
    -----------------------------------------------------------------------------------------------------------------
    --  MAIN HANDLER
    SAMPLER:    process(sysClk)
                begin
                    if (rising_edge(sysClk)) then
                        case (r_stage) is
                            when s_INIT =>
                                ss_run <= run;
                                ss_reset <= reset;
                                ss_sync_0 <= '0';
                            
                            when s_STAT =>
                                ss_run <= run;
                                ss_reset <= reset;
                            
                            when s_IF_0 =>
                                ss_sync_0 <= '0';
                            
                            when s_IF_1 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_data <= s_bus_out_data;
                                ss_sync_0 <= '0';
                                
                            when s_IF_2 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_OF_GPREG_1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                            
                            when s_OF_GPREG_2 =>
                                ss_reg_drdy <= s_reg_drdy;
                            
                            when s_OF_GPREG_3 =>
                                ss_xlm_drdy <= s_xlm_drdy;
                                ss_xlm_data_out <= s_xlm_data_out;
                            
                            when s_OF_GPREG_4 =>
                                ss_xlm_drdy <= s_xlm_drdy;
                            
                            when s_OF_BUS_1 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_done <= s_bus_out_done;
                                ss_bus_out_data <= s_bus_out_data;
                            
                            when s_OF_BUS_2 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_WBACK_IN_GPREG_1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                                ss_reg_data_fr <= s_reg_data_fr;
                                
                            when s_WBACK_IN_GPREG_2 =>
                                ss_reg_drdy <= s_reg_drdy;
                            
                            when s_WBACK_IN_BUS_1 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                                ss_bus_out_done <= s_bus_out_done;
                                ss_bus_out_data <= s_bus_out_data;
                            
                            when s_WBACK_IN_BUS_2 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_WBACK_GPREG_1 =>
                                ss_reg_drdy <= s_reg_drdy;
                                ss_reg_done <= s_reg_done;
                            
                            when s_WBACK_GPREG_2 =>
                                ss_reg_drdy <= s_reg_drdy;
                            
                            when s_WBACK_GPREG_3 =>
                                ss_xlm_drdy <= s_xlm_drdy;
                            
                            when s_WBACK_GPREG_4 =>
                                ss_xlm_drdy <= s_xlm_drdy;
                            
                            when s_WBACK_BUS_1 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_WBACK_BUS_2 =>
                                ss_bus_out_drdy <= s_bus_out_drdy;
                            
                            when s_IRC =>
                                ss_irq_prepare <= irq_prepare;
                                ss_sync_0 <= '1';
                            
                            when s_HLT =>
                                ss_run <= run;
                            
                            when s_IRH_PRE =>
                                ss_irq_prepare <= irq_prepare;
                                ss_sync_0 <= '0';
                            
                            when s_IRH_0 =>
                                ss_irq_vector_drdy <= irq_vector_drdy;
                                ss_irq_vector_done <= irq_vector_done;
                                ss_irq_vector_bus <= irq_vector_bus;
                                ss_sync_0 <= '1';
                            
                            when s_IRH_1 =>
                                ss_irq_vector_drdy <= irq_vector_drdy;
                                ss_sync_0 <= '0';
                            
                            when s_IRH_2 =>
                                ss_irq_active_wait <= irq_active_wait;
                            
                            when s_IRH_3 =>
                                ss_irq_active_wait <= irq_active_wait;
                                                                                    
                            when others =>
                                null;
                        end case;
                    end if;
                end process SAMPLER;
       
    MAIN:       process(sysClk)
                    --  counters
                    variable c: natural := 0;
                    variable d: natural := 0;
                    variable e: natural := 0;
                    variable f0: natural := 0;
                    variable f1: natural := 0;
                    variable h: natural := 0;
                    variable ha: std_logic_vector(addr_width-1 downto 0) := (others=>'0');
                    --  placeholders
                    variable am: std_logic_vector(1 downto 0) := "00";  --  00 : immediate, 01 : direct, 10 : indirect
                    variable ds: natural := 0;                          --  data size in bytes (1,2 or 4)
                    variable addr: natural := 0;                        --  placeholder for address
                    variable pvt: std_logic := '0';
                    variable spk: std_logic := '0';
                    variable pidx: std_logic_vector(1 downto 0) := "00";
                    variable special_reg: std_logic_vector(2 downto 0) := "000";
                    variable full_reg: std_logic_vector(3 downto 0) := "0000";
                    variable this_addr: natural := 0;
                    variable isr_active: std_logic := '0';
                    variable instr_counter: natural := 0;
                    variable debug_thing: std_logic_vector(7 downto 0);
                    variable cond: std_logic_vector(1 downto 0);
                begin
                    if (rising_edge(sysClk)) then
                        if (sysRstb='0') then
                            r_stage <= s_INIT;
                        else
                            case (r_stage) is
                                --  cpu initialization
                                when s_INIT =>
                                    --  system bus controls
                                    r_dbg_instr <= 0;
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
                                    --  initializing special registers
                                    r_acc <= (others=>'0');
                                    r_tmp_1 <= (others=>'0');
                                    r_tmp_2 <= (others=>'0');
                                    r_flag_stat <= (others=>'0');
                                    r_pc <= reset_vector;
                                    r_sp <= 0;
                                    r_aluB_data <= (others=>'0');
                                    r_opC_jump <= (others=>'0');
                                    --  initializing non addressable registers
                                    r_instr_word <= (others=>'0');
                                    r_opA_addr <= (others=>'0');
                                    r_opB_addr <= (others=>'0');
                                    r_opA_data <= (others=>'0');
                                    r_opB_data <= (others=>'0');
                                    --  auxiliary
                                    r_op_data <= (others=>'0');
                                    r_op_addr <= (others=>'0');
                                    --  preparing counters
                                    c := 0;
                                    d := 0;
                                    e := 0;
                                    am := "00";
                                    ds := 0;
                                    addr := 0;
                                    pvt := '0';
                                    pidx := "00";
                                    special_reg := "000";
                                    isr_active := '0';
                                    --  interrupt vector sampler
                                    r_irq_vector_ack <= '0';
                                    r_irq_active <= '0';
                                    --  halt
                                    r_HLT <= '0';
                                    --  waiting for run-pause signal
                                    if ((ss_run='1') and (ss_reset='0')) then
                                        r_stage <= s_IF_0;
                                    else
                                        r_stage <= s_INIT;
                                    end if;
                                
                                when s_STAT =>
                                    --  check the run/pause/reset signals
                                    cond := (ss_run & ss_reset);
                                    case (cond) is
                                        when "10" =>
                                            r_stage <= s_IF_0;
                                        
                                        when "00" =>
                                            r_stage <= s_STAT;
                                        
                                        when "01" =>
                                            r_stage <= s_INIT;
                                        
                                        when others =>
                                            r_stage <= s_STAT;
                                    end case;
                                                                                             
                                --  instruction word fetch
                                --  the 80 bits instruction word is fetched at once                                
                                when s_IF_0 =>
                                    r_dbg_instr <= 1;
                                    --  fetching an instruction bit to put into the word
                                    r_bus_in_cmd <= '1';
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_addr <= std_logic_vector(to_unsigned(r_pc, addr_width));
                                    if (c=9) then
                                        r_bus_in_keep <= '0';
                                    else
                                        r_bus_in_keep <= '1';
                                    end if;
                                    r_stage <= s_IF_1;
                                         
                                when s_IF_1 =>
                                    r_dbg_instr <= 2;
                                    if (ss_bus_out_drdy='1') then
                                        --  sram responded, so
                                        r_instr_word(((c+1)*8)-1 downto (c*8)) <= ss_bus_out_data;
                                        r_stage <= s_IF_2;
                                    else
                                        --  waiting for SRAM
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_IF_1;
                                    end if;
                                
                                when s_IF_2 =>
                                    r_dbg_instr <= 3;
                                    if (ss_bus_out_drdy='0') then
                                        --  checking
                                        if (c=9) then
                                            --  instruction word is complete, so
                                            c := 0;
                                            --  fanning the addresses
                                            r_opA_addr <= r_instr_word(23 downto 0);
                                            r_opB_addr <= r_instr_word(47 downto 24);
                                            r_opC_jump <= r_instr_word(71 downto 48);
                                            r_stage <= s_CHK_A;
                                        else
                                            --  need to go again
                                            c := c + 1;
                                            r_pc <= r_pc + 1;
                                            r_stage <= s_IF_0;
                                        end if;
                                    else
                                        --  going to next one
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_IF_2;
                                    end if;
                                                                                                                
                                when s_CHK_A =>
                                    r_dbg_instr <= 4;
                                    addr := to_integer(unsigned(r_opA_addr(addr_width-1 downto 0)));
                                    am := r_instr_word(73 downto 72);
                                    case (am) is
                                        when "00" =>
                                            --  immediate addressing : no modification regardless, since it's just a number
                                            r_opA_addr <= r_opA_addr;
                                            r_pvt(0) <= '0';
                                        
                                        when "01" =>
                                            --  direct addressing : must remove the offset if it lies inside
                                            if ((addr >= cpu_private_begin) and (addr <= cpu_private_end)) then
                                                r_opA_addr <= std_logic_vector(to_unsigned(addr - cpu_private_begin, addr_width+1));
                                                r_pvt(0) <= '1';
                                            else
                                                r_opA_addr <= r_opA_addr;
                                                r_pvt(0) <= '0';
                                            end if;
                                        
                                        when "10" =>
                                            --  indirect addressing _ must remove the offset
                                            if ((addr >= cpu_private_begin) and (addr <= cpu_private_end)) then
                                                r_opA_addr <= std_logic_vector(to_unsigned(addr - cpu_private_begin, addr_width+1));
                                                r_pvt(0) <= '1';
                                            else
                                                r_opA_addr <= r_opA_addr;
                                                r_pvt(0) <= '0';
                                            end if;
                                    
                                        when others =>
                                            null;
                                    end case;
                                    r_stage <= s_CHK_B;
                                
                                when s_CHK_B =>
                                    r_dbg_instr <= 5;
                                    addr := to_integer(unsigned(r_opB_addr(addr_width-1 downto 0)));
                                    am := r_instr_word(75 downto 74);
                                    case (am) is
                                        when "00" =>
                                            --  immediate addressing : no modification regardless, since it's just a number
                                            r_opB_addr <= r_opB_addr;
                                            r_pvt(1) <= '0';
                                        
                                        when "01" =>
                                            --  direct addressing : must remove the offset if it lies inside
                                            if ((addr >= cpu_private_begin) and (addr <= cpu_private_end)) then
                                                r_opB_addr <= std_logic_vector(to_unsigned(addr - cpu_private_begin, addr_width+1));
                                                r_pvt(1) <= '1';
                                            else
                                                r_opB_addr <= r_opB_addr;
                                                r_pvt(1) <= '0';
                                            end if;
                                        
                                        when "10" =>
                                            --  indirect addressing _ must remove the offset
                                            if ((addr >= cpu_private_begin) and (addr <= cpu_private_end)) then
                                                r_opB_addr <= std_logic_vector(to_unsigned(addr - cpu_private_begin, addr_width+1));
                                                r_pvt(1) <= '1';
                                            else
                                                r_opB_addr <= r_opB_addr;
                                                r_pvt(1) <= '0';
                                            end if;
                                    
                                        when others =>
                                            null;
                                    end case;
                                    r_stage <= s_CHK_C;
                                
                                when s_CHK_C =>
                                    r_dbg_instr <= 6;
                                    addr := to_integer(unsigned(r_opC_jump(addr_width-1 downto 0)));
                                    am := "0"&r_opC_jump(addr_width);
                                    case (am) is
                                        when "00" =>
                                            --  immediate addressing : no modification regardless, since it's just a number
                                            r_opC_jump <= r_opC_jump;
                                            r_pvt(2) <= '0';
                                        
                                        when "01" =>
                                            --  direct addressing : must remove the offset if it lies inside
                                            if ((addr >= cpu_private_begin) and (addr <= cpu_private_end)) then
                                                r_opC_jump(addr_width-1 downto 0) <= std_logic_vector(to_unsigned(addr - cpu_private_begin, addr_width));
                                                r_pvt(2) <= '1';
                                            else
                                                r_opC_jump <= r_opC_jump;
                                                r_pvt(2) <= '0';
                                            end if;
                                    
                                        when others =>
                                            null;
                                    end case;
                                    r_stage <= s_FETCH_A;
                                
                                when s_FETCH_A =>
                                    r_dbg_instr <= 7;
                                    am := r_instr_word(73 downto 72);                           --  A operand addressing mode
                                    ds := to_integer(unsigned(r_instr_word(77 downto 76))) + 1; --  number of bytes to retrieve
                                    addr := to_integer(unsigned(r_opA_addr(addr_width-1 downto 0)));                   --  placeholder for address   
                                    pvt := r_pvt(0);
                                    pidx := std_logic_vector(to_unsigned(0, 2));
                                    --  initializing and preparing registers
                                    r_opA_data <= (others=>'0');
                                    r_op_addr <= r_opA_addr(addr_width-1 downto 0);
                                    r_op_data <= (others=>'0');
                                    --  going
                                    r_jump_1 <= s_FETCH_B;
                                    r_stage <= s_OF_0;
                                    
                                when s_FETCH_B =>
                                    r_dbg_instr <= 8;
                                    am := r_instr_word(75 downto 74);
                                    ds := to_integer(unsigned(r_instr_word(79 downto 78))) + 1;
                                    addr := to_integer(unsigned(r_opB_addr(addr_width-1 downto 0)));
                                    pvt := r_pvt(1);
                                    pidx := std_logic_vector(to_unsigned(1, 2));
                                    --  initializing and preparing registers
                                    r_opB_data <= (others=>'0');
                                    r_op_addr <= r_opB_addr(addr_width-1 downto 0);
                                    r_op_data <= (others=>'0');
                                    --  going
                                    r_jump_1 <= s_FETCH_C;
                                    r_stage <= s_OF_0;
                                
                                when s_FETCH_C =>
                                    r_dbg_instr <= 9;                                    
                                    am := "0"&r_opC_jump(23);
                                    ds := 4;
                                    addr := to_integer(unsigned(r_opC_jump(addr_width-1 downto 0)));
                                    pvt := r_pvt(2);
                                    pidx := std_logic_vector(to_unsigned(2, 2));
                                    --  initializing and preparing registers                                        
                                    r_op_addr <= r_opC_jump(addr_width-1 downto 0);
                                    r_op_data <= (others=>'0');
                                    --  going
                                    r_jump_1 <= s_EXEC_0;
                                    r_stage <= s_OF_0;
                                                   
                                --  Operand Fetch
                                --  Now, according to the specified operands' addressing modes, they are retrieved.
                                when s_OF_0 =>
                                    r_dbg_instr <= 10;
                                    case (am) is
                                        when "00" =>
                                            --  immediate : the operand address that appears in the instruction word is the data itself (limited to 23 bits)
                                            r_op_data(22 downto 0) <= r_op_addr;
                                            r_op_data(31 downto 23) <= (others=>'0');
                                            r_jump_0 <= r_jump_1;
                                            r_stage <= s_OF_COMMON;
                                        
                                        when "01" =>
                                            --  direct: the operand address must be placed on the bus to retrieve its value
                                            --  checking if it is for a special register, a general purpose one or the external bus
                                            c := 0;
                                            r_jump_0 <= r_jump_1;
                                            --  VERIFICARE SE E' PRIVATO O MENO. SE NON E' PRIVATO DEVO ANDARE PER FORZA SUL BUS
                                            if (pvt='1') then
                                                if ((addr < 8) or (addr > 65)) then
                                                    --  special register
                                                    r_stage <= s_OF_SREG_0;
                                                else
                                                    --  internal cpu register
                                                    r_stage <= s_OF_GPREG_0;
                                                end if;
                                            else
                                                --  if it's not private, it means that it has to go to the bus
                                                r_stage <= s_OF_BUS_0;
                                            end if;
                                        
                                        when "10" =>
                                            --  indirect mode: the operand address points to a memory location where another memory location is stored and that actually returns the data, so
                                            c := 0;
                                            r_jump_0 <= s_OF_IN_0;
                                            if (pvt='1') then
                                                if ((addr < 8) or (addr > 65)) then
                                                    --  special register contains the address
                                                    r_stage <= s_OF_SREG_0;
                                                else
                                                    --  internal cpu register stores the address
                                                    r_stage <= s_OF_GPREG_0;
                                                end if;
                                            else
                                                --  if it's not private, it means that it has to go to the bus
                                                r_stage <= s_OF_BUS_0;
                                            end if;
                                        
                                        when "11" =>
                                            --  invalid instruction: addressing mode is not supported.
                                            r_stage <= s_ERR;
                                    end case;
                                
                                when s_ERR =>
                                    r_dbg_instr <= 170;
                                    r_stage <= s_ERR;
                                                                
                                when s_OF_IN_0 =>
                                    r_dbg_instr <= 11;
                                    if (d=0) then
                                        --  the data we just fetched must be interpreted as address so:
                                        d := 1;
                                        --  I have to first check if I need to do reductions, so:
                                        addr := to_integer(unsigned(r_op_data(addr_width-1 downto 0)));
                                        if ((addr >= cpu_private_begin) and (addr <= cpu_private_end)) then
                                            --  need to also reduce this, so:
                                            r_op_addr <= std_logic_vector(to_unsigned(addr - cpu_private_begin, addr_width));
                                            pvt := '1';
                                        else
                                            --  no need to reduce
                                            r_op_addr <= r_op_data(addr_width-1 downto 0);
                                            pvt := '0';
                                        end if;
                                        r_stage <= s_OF_0;
                                    else
                                        --  we now have the actual data, so ready to go forward
                                        d := 0;
                                        r_stage <= r_jump_1;
                                    end if;
                                
                                when s_OF_SREG_0 =>
                                    r_dbg_instr <= 12;
                                    --  acting on the special registers
                                    if (addr < 8) then
                                        --  first kind registers
                                        special_reg := r_op_addr(2 downto 0);
                                        spk := '0';
                                    else
                                        --  interrupt data registers
                                        special_reg := std_logic_vector(to_unsigned(addr - 66, 3));
                                        spk := '1';
                                    end if;
                                    --  checking what we have
                                    full_reg := spk & special_reg;
                                    case (full_reg) is
                                        when "0000" =>
                                            --  accumulator: 32 bit wide
                                            r_op_data <= r_acc;
                                        
                                        when "0001" =>
                                            --  temporary 1: 32 bit wide
                                            r_op_data <= r_tmp_1;
                                        
                                        when "0010" =>
                                            --  temporary 2: 32 bit wide
                                            r_op_data <= r_tmp_2;
                                        
                                        when "0011" =>
                                            --  flag and status: 8 bit wide
                                            r_op_data(31 downto 8) <= (others=>'0');
                                            r_op_data(7 downto 0) <= r_flag_stat;
                                        
                                        when "0100" =>
                                            --  program counter: 32 bit wide : this saves the program counter at the end of the previous instruction
                                            r_op_data <= std_logic_vector(to_unsigned(r_pc_back, 32));
                                        
                                        when "0101" =>
                                            --  stack pointer: 32 bit wide
                                            r_op_data <= std_logic_vector(to_unsigned(r_sp, 32));
                                        
                                        when "0110" =>
                                            --  alu B data: 32 bit wide
                                            r_op_data <= r_aluB_data;
                                        
                                        when "0111" =>
                                            --  jump register: 23 bit wide
                                            r_op_data(31 downto (addr_width+1)) <= (others=>'0');
                                            r_op_data(addr_width downto 0) <= r_opC_jump;
                                            
                                        --  now the cases for the ISRI
                                        when "1000" =>
                                            --  interrupt input register 1
                                            r_op_data <= isr_file(0);
                                        
                                        when "1001" =>
                                            --  interrupt input register 2
                                            r_op_data <= isr_file(1);
                                        
                                        when "1010" =>
                                            --  interrupt input register 3
                                            r_op_data <= isr_file(2);
                                        
                                        when "1011" =>
                                            --  interrupt input register 4
                                            r_op_data <= isr_file(3);
                                        
                                        when "1100" =>
                                            --  interrupt input register 5
                                            r_op_data <= isr_file(4);
                                        
                                        when "1101" =>
                                            --  interrupt input register 6
                                            r_op_data <= isr_file(5);
                                        
                                        --  scratchpad registers
                                        when "1110" =>
                                            --  scratchpad 0
                                            r_op_data <= isr_file(6);
                                        
                                        when "1111" =>
                                            --  scratchpad 1
                                            r_op_data <= isr_file(7);                                            
                                        
                                        when others =>
                                            r_op_data <= (others=>'0');
                                        
                                    end case;
                                    --  going ahead
                                    r_stage <= s_OF_COMMON;
                                                                
                                when s_OF_GPREG_0 =>
                                    r_dbg_instr <= 13;
                                    --  checking if it is for the registers or for the extended logical module
                                    this_addr := to_integer(unsigned(r_op_addr(7 downto 0)));
                                    if (this_addr < 56) then
                                        --  setting up the internal register controls
                                        r_reg_cmd <= '1';
                                        r_reg_addr <= std_logic_vector(to_unsigned(this_addr-8, 8));
                                        r_reg_data_to <= (others=>'0');
                                        r_stage <= s_OF_GPREG_1;
                                    else
                                        --  setting up the extended logical module
                                        r_xlm_cmd <= '1';
                                        r_xlm_addr <= std_logic_vector(to_unsigned(this_addr-56, 4));
                                        r_xlm_data_in <= (others=>'0');
                                        r_stage <= s_OF_GPREG_3;
                                    end if;
                                          
                                when s_OF_GPREG_1 =>
                                    r_dbg_instr <= 14;
                                    if (ss_reg_drdy='1') then
                                        r_op_data(((c+1)*8)-1 downto (c*8)) <= s_reg_data_fr;
                                        r_stage <= s_OF_GPREG_2;
                                    else
                                        r_reg_latch <= '1';
                                        r_stage <= s_OF_GPREG_1;
                                    end if;
                                
                                when s_OF_GPREG_2 =>
                                    r_dbg_instr <= 15;
                                    if (ss_reg_drdy='0') then
                                        if (ss_reg_done='1') then
                                            --  all done
                                            c := 0;
                                            r_stage <= s_OF_COMMON;
                                        else
                                            --  going for another
                                            c := c + 1;
                                            r_stage <= s_OF_GPREG_1;
                                        end if;
                                    else
                                        r_reg_latch <= '0';
                                        r_stage <= s_OF_GPREG_2;
                                    end if;
                                
                                when s_OF_GPREG_3 =>
                                    r_dbg_instr <= 64;
                                    if (ss_xlm_drdy='1') then
                                        r_op_data <= ss_xlm_data_out;
                                        r_stage <= s_OF_GPREG_4;
                                    else
                                        r_xlm_latch <= '1';
                                        r_stage <= s_OF_GPREG_3;
                                    end if;
                                
                                when s_OF_GPREG_4 =>
                                    r_dbg_instr <= 65;
                                    if (ss_xlm_drdy='0') then
                                        --  all done
                                        r_stage <= s_OF_COMMON;
                                    else
                                        r_xlm_latch <= '0';
                                        r_stage <= s_OF_GPREG_4;
                                    end if;

                                when s_OF_BUS_0 =>
                                    r_dbg_instr <= 16;
                                    --  setting up the bus or the internal register, let's see
                                    r_bus_in_cmd <= '1';
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_addr <= r_op_addr;
                                    --  the cpu always initializes single transactions here
                                    r_bus_in_keep <= '0';
                                    r_stage <= s_OF_BUS_1;
                                                                                                                                
                                when s_OF_BUS_1 =>
                                    r_dbg_instr <= 17;
                                    if (ss_bus_out_drdy='1') then
                                        --  receiving data
                                        r_op_data(((c+1)*8)-1 downto (c*8)) <= ss_bus_out_data;
                                        r_stage <= s_OF_BUS_2;
                                    else
                                        --  latching the command
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_OF_BUS_1;
                                    end if;
                                
                                when s_OF_BUS_2 =>
                                    r_dbg_instr <= 18;
                                    if (ss_bus_out_drdy='0') then
                                        --  checking
                                        if (ss_bus_out_done='1') then
                                            --  op retrieval is complete, so need now to see where to pin this data
                                            c := 0;
                                            r_stage <= s_OF_COMMON;
                                        else
                                            --  need to go again
                                            c := c + 1;
                                            r_stage <= s_OF_BUS_1;
                                        end if;
                                    else
                                        --  waiting
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_OF_BUS_2;
                                    end if;
                                
                                when s_OF_COMMON =>
                                    r_dbg_instr <= 19;
                                    case (pidx) is
                                        when "00" =>
                                            r_opA_data <= r_op_data;
                                        
                                        when "01" =>
                                            r_opB_data <= r_op_data;
                                        
                                        when "10" =>
                                            r_opC_jump <= r_op_data(addr_width downto 0);
                                        
                                        when others =>
                                            r_op_data <= r_op_data;
                                    end case;
                                    r_stage <= r_jump_0;
                                         
                                --  execute
                                --  now we have both the data and the addresses of the two operands and we must perform the SUBLEQ instruction.
                                --  the subleq instruction is just B - A. The A operand is already internally inverted and summed in a CA2 fashion with B
                                --  the result of the summation has to overwrite B at its memory location and the overflow flag needs to be written on the
                                --  status register.
                                when s_EXEC_0 =>
                                    r_dbg_instr <= 20;
                                    --  preparing the input to the ALU : this is given by opB data
                                    r_aluB_data <= r_opB_data;
                                    --  preparing some stuff in advance for the writeback
                                    addr := to_integer(unsigned(r_opB_addr));
                                    am := r_instr_word(75 downto 74);
                                    ds := to_integer(unsigned(r_instr_word(79 downto 78))) + 1;
                                    c := 0;
                                    --  setting the alu data size
                                    r_alu_ds <= ds*8;
                                    --  let's execute the instruction
                                    r_stage <= s_EXEC_1;
                                
                                when s_EXEC_1 =>
                                    r_dbg_instr <= 21;
                                    --  updating the cpu status flags
                                    r_flag_stat(7) <= s_fadd_ovf;       --  overflow
                                    r_flag_stat(6) <= s_fadd_zf;        --  zero
                                    r_flag_stat(5) <= s_fadd_sf;        --  sign
                                    r_flag_stat(4) <= s_fadd_pf;        --  parity
                                    --  saving B-A onto B again and now we must perform the writeback operation                                                                        
                                    r_opB_data <= s_fadd_sum;
                                    --  going to writeback
                                    r_stage <= s_EXEC_2;
                                
                                when s_EXEC_2 =>
                                    r_dbg_instr <= 128;
                                    --  writeback depends on the target writeback address and the addressing mode of the target, so                                    
                                    --  let's check the addressing mode (direct or indirect)
                                    c := 0;
                                    r_op_data <= (others=>'0');
                                    case (am) is
                                        when "01" =>
                                            --  direct
                                            if (r_pvt(1)='1') then
                                                --  the writeback operand is a private cpu thing, so
                                                if ((addr < 8) or (addr > 65)) then
                                                    --  special register
                                                    r_stage <= s_WBACK_SREG_0;
                                                else
                                                    r_stage <= s_WBACK_GPREG_0;
                                                end if;
                                            else
                                                --  external
                                                r_stage <= s_WBACK_BUS_0;
                                            end if;
                                        
                                        when "10" =>
                                            --  indirect -> we need to first get the true address onto which to write
                                            if (r_pvt(1)='1') then
                                                --  the writeback operand is a private cpu thing, so
                                                if ((addr < 8) or (addr > 65)) then
                                                    --  special register
                                                    r_stage <= s_WBACK_IN_SREG_0;
                                                else
                                                    r_stage <= s_WBACK_IN_GPREG_0;
                                                end if;
                                            else
                                                --  external
                                                r_stage <= s_WBACK_IN_BUS_0;
                                            end if;
                                        
                                        when others =>
                                            --  this will cause cpu halt with error
                                            null;
                                    end case;
                                
                                when s_WBACK_IN_SREG_0 =>
                                    r_dbg_instr <= 129;
                                    --  in this case, the special registers hold the address onto which we have to operate, so
                                    if (addr < 8) then
                                        --  first kind registers
                                        special_reg := r_opB_addr(2 downto 0);
                                        spk := '0';
                                    else
                                        --  interrupt data registers
                                        special_reg := std_logic_vector(to_unsigned(addr - 66, 3));
                                        spk := '1';
                                    end if;
                                    --  checking what we have
                                    full_reg := spk & special_reg;
                                    --  checking
                                    case (full_reg) is
                                        when "0000" =>
                                            --  accumulator stores the WB address in its value
                                            r_op_data <= r_acc;
                                        
                                        when "0001" =>
                                            --  temporary 1
                                            r_op_data <= r_tmp_1;
                                        
                                        when "0010" =>
                                            --  temporary 2
                                            r_op_data <= r_tmp_2;
                                                                                
                                        when "0101" =>
                                            --  stack pointer
                                            r_op_data(31 downto addr_width) <= (others=>'0');
                                            r_op_data(addr_width-1 downto 0) <= std_logic_vector(to_unsigned(r_sp, addr_width));
                                        
                                        when "0110" =>
                                            --  alu B data
                                            r_op_data <= r_aluB_data;
                                        
                                        when "0111" =>
                                            --  jump register
                                            r_op_data(31 downto addr_width+1) <= (others=>'0');
                                            r_op_data(addr_width downto 0) <= r_opC_jump;
                                        
                                        --  ISRI
                                        when "1000" =>
                                            --  using ISRI0 as address source
                                            r_op_data <= isr_file(0);
                                        
                                        when "1001" =>
                                            --  using ISRI1 as address source
                                            r_op_data <= isr_file(1);
                                            
                                        when "1010" =>
                                            --  using ISRI2 as address source
                                            r_op_data <= isr_file(2);
                                            
                                        when "1011" =>
                                            --  using ISRI3 as address source
                                            r_op_data <= isr_file(3);
                                            
                                        when "1100" =>
                                            --  using ISRI4 as address source
                                            r_op_data <= isr_file(4);
                                        
                                        when "1101" =>
                                            --  using ISRI5 as address source
                                            r_op_data <= isr_file(5);
                                        
                                        --  scratchpad registers
                                        when "1110" =>
                                            --  using SCR0 as address source
                                            r_op_data <= isr_file(6);
                                        
                                        when "1111" =>
                                            --  using SCR1 as address source
                                            r_op_data <= isr_file(7);
                                                                                                                                                           
                                        when others =>
                                            --  this will cause cpu halt and error
                                            null;
                                    end case;
                                    r_stage <= s_WBACK_IN_PRE;
                                
                                when s_WBACK_IN_PRE =>
                                    r_dbg_instr <= 130;
                                    --  need now to see the address and perform update
                                    am := "01";
                                    addr := to_integer(unsigned(r_op_data(addr_width-1 downto 0)));
                                    if ((addr >= cpu_private_begin) and (addr <= cpu_private_end)) then
                                        --  the target writeback is private
                                        r_opB_addr(addr_width) <= '0';
                                        r_opB_addr(addr_width-1 downto 0) <= std_logic_vector(to_unsigned(addr - cpu_private_begin, addr_width));
                                        r_pvt(1) <='1';
                                    else
                                        --  no need to reduce
                                        r_opB_addr(addr_width) <= '0';
                                        r_opB_addr(addr_width-1 downto 0) <= r_op_data(addr_width-1 downto 0);
                                        r_pvt(1) <= '0';
                                    end if;
                                    --  we can go
                                    r_stage <= s_EXEC_2;
                                
                                when s_WBACK_IN_GPREG_0 =>
                                    r_dbg_instr <= 131;
                                    --  in this case we have to retrieve the address stored in a general purpose register (eax, ebx, ecx, ecc)
                                    this_addr := to_integer(unsigned(r_opB_addr(7 downto 0)));
                                    r_reg_cmd <= '1';
                                    r_reg_addr <= std_logic_vector(to_unsigned(this_addr-8, 8));
                                    r_reg_data_to <= (others=>'0');
                                    r_stage <= s_WBACK_IN_GPREG_1;
                                
                                when s_WBACK_IN_GPREG_1 =>
                                    r_dbg_instr <= 132;
                                    if (ss_reg_drdy='1') then
                                        --  we have the data from the register, we need to use it to compose r_opB_addr                                        
                                        r_op_data(((c+1)*8)-1 downto (c*8)) <= ss_reg_data_fr;
                                        r_stage <= s_WBACK_IN_GPREG_2;
                                    else
                                        --  writing
                                        r_reg_latch <= '1';
                                        r_stage <= s_WBACK_IN_GPREG_1;
                                    end if;

                                when s_WBACK_IN_GPREG_2 =>
                                    r_dbg_instr <= 133;
                                    if (ss_reg_drdy='0') then
                                        if (ss_reg_done='1') then
                                            --  we have the whole address, so we can assemble it
                                            c := 0;
                                            r_stage <= s_WBACK_IN_PRE;
                                        else
                                            --  read more of the address
                                            c := c + 1;
                                            r_stage <= s_WBACK_IN_GPREG_1;
                                        end if;
                                    else
                                        --  waiting
                                        r_reg_latch <= '0';
                                        r_stage <= s_WBACK_IN_GPREG_2;
                                    end if;
                                
                                when s_WBACK_IN_BUS_0 =>
                                    r_dbg_instr <= 134;
                                    r_bus_in_cmd <= '1';
                                    r_bus_in_addr <= r_opB_addr(addr_width-1 downto 0);
                                    r_bus_in_data <= (others=>'0');
                                    r_bus_in_keep <= '0';
                                    r_stage <= s_WBACK_IN_BUS_1;
                                                                
                                when s_WBACK_IN_BUS_1 =>
                                    r_dbg_instr <= 135;
                                    if (ss_bus_out_drdy='1') then
                                        --  done reading
                                        r_op_data(((c+1)*8)-1 downto (c*8)) <= ss_bus_out_data;
                                        r_stage <= s_WBACK_IN_BUS_2;
                                    else
                                        --  waiting
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_WBACK_IN_BUS_1;
                                    end if;
                                
                                when s_WBACK_IN_BUS_2 =>
                                    r_dbg_instr <= 136;
                                    if (ss_bus_out_drdy='0') then
                                        if (ss_bus_out_done='1') then
                                            --  it was the last to be read
                                            c := 0;
                                            r_stage <= s_WBACK_IN_PRE;
                                        else
                                            --  need to read more
                                            c := c + 1;
                                            r_stage <= s_WBACK_IN_BUS_1;
                                        end if;
                                    else
                                        --  waiting
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_WBACK_IN_BUS_2;
                                    end if;
                                
                                ---------------------------------------------------------
                                --  DIRECT ADDRESSING WRITEBACK
                                when s_WBACK_SREG_0 =>
                                    r_dbg_instr <= 22;
                                    --  checking the addressing mode
                                    if (addr < 8) then
                                        --  first kind registers
                                        special_reg := r_opB_addr(2 downto 0);
                                        spk := '0';
                                    else
                                        --  interrupt data registers
                                        special_reg := std_logic_vector(to_unsigned(addr - 66, 3));
                                        spk := '1';
                                    end if;
                                    --  checking what we have
                                    full_reg := spk & special_reg;
                                    --  direct addressing mode
                                    case (full_reg) is
                                        when "0000" =>
                                            --  accumulator writeback
                                            r_acc <= r_opB_data;
                                        
                                        when "0001" =>
                                            --  temporary 1
                                            r_tmp_1 <= r_opB_data;
                                        
                                        when "0010" =>
                                            --  temporary 2
                                            r_tmp_2 <= r_opB_data;
                                        
                                        when "0011" =>
                                            --  flag and status
                                            r_flag_stat <= r_opB_data(7 downto 0);
                                        
                                        when "0100" =>
                                            --  program counter (actually it is the 'back' one)
                                            r_pc_back <= to_integer(unsigned(r_opB_data));
                                        
                                        when "0101" =>
                                            --  stack pointer
                                            r_sp <= to_integer(unsigned(r_opB_data));
                                        
                                        when "0110" =>
                                            --  alu B data
                                            r_aluB_data <= r_opB_data;
                                        
                                        when "0111" =>
                                            --  jump register
                                            r_opC_jump <= r_opB_data(addr_width downto 0);
                                        
                                        --  ISRI
                                        when "1000" =>
                                            --  interrupt input register 1
                                            isr_file(0) <= r_opB_data;
                                        
                                        when "1001" =>
                                            --  interrupt input register 2
                                            isr_file(1) <= r_opB_data;
                                        
                                        when "1010" =>
                                            --  interrupt input register 3
                                            isr_file(2) <= r_opB_data;
                                        
                                        when "1011" =>
                                            --  interrupt input register 4
                                            isr_file(3) <= r_opB_data;
                                        
                                        when "1100" =>
                                            --  interrupt input register 5
                                            isr_file(4) <= r_opB_data;
                                        
                                        when "1101" =>
                                            --  interrupt input register 6
                                            isr_file(5) <= r_opB_data;
                                        
                                        when "1110" =>
                                            --  scratchpad register 0
                                            isr_file(6) <= r_opB_data;
                                        
                                        when "1111" =>
                                            --  scratchpad register 1
                                            isr_file(7) <= r_opB_data;
                                        
                                        when others =>
                                            null;
                                    end case;
                                    r_stage <= s_JMP;
                                
                                when s_WBACK_GPREG_0 =>                                    
                                    r_dbg_instr <= 23;
                                    this_addr := to_integer(unsigned(r_opB_addr(7 downto 0)));
                                    if (this_addr < 56) then
                                        --  local registers
                                        r_reg_cmd <= '0';
                                        r_reg_addr <= std_logic_vector(to_unsigned(this_addr-8, 8));
                                        r_reg_data_to <= r_opB_data(((c+1)*8)-1 downto (c*8));
                                        r_stage <= s_WBACK_GPREG_1;
                                    else
                                        --  extended logical module
                                        r_xlm_cmd <= '0';
                                        r_xlm_addr <= std_logic_vector(to_unsigned(this_addr-56, 4));
                                        r_xlm_data_in <= r_opB_data;
                                        r_stage <= s_WBACK_GPREG_3;
                                    end if;

                                when s_WBACK_GPREG_1 =>
                                    r_dbg_instr <= 24;
                                    if (ss_reg_drdy='1') then
                                        --  data written on the register
                                        r_stage <= s_WBACK_GPREG_2;
                                    else
                                        --  writing
                                        r_reg_latch <= '1';
                                        r_stage <= s_WBACK_GPREG_1;
                                    end if;

                                when s_WBACK_GPREG_2 =>
                                    r_dbg_instr <= 25;
                                    if (ss_reg_drdy='0') then
                                        if (ss_reg_done='1') then
                                            --  must terminate write, so
                                            c := 0;
                                            r_stage <= s_JMP;
                                        else
                                            --  write more
                                            c := c + 1;
                                            r_stage <= s_WBACK_GPREG_0;
                                        end if;
                                    else
                                        --  waiting
                                        r_reg_latch <= '0';
                                        r_stage <= s_WBACK_GPREG_2;
                                    end if;
                                
                                when s_WBACK_GPREG_3 =>
                                    r_dbg_instr <= 66;
                                    if (ss_xlm_drdy='1') then
                                        --  data written
                                        r_stage <= s_WBACK_GPREG_4;
                                    else
                                        --  writing
                                        r_xlm_latch <= '1';
                                        r_stage <= s_WBACK_GPREG_3;
                                    end if;
                                    
                                when s_WBACK_GPREG_4 =>
                                    r_dbg_instr <= 67;
                                    if (ss_xlm_drdy='0') then
                                        --  end of writeback
                                        r_stage <= s_JMP;
                                    else
                                        r_xlm_latch <= '0';
                                        r_stage <= s_WBACK_GPREG_4;
                                    end if;
                            
                                when s_WBACK_BUS_0 =>
                                    r_dbg_instr <= 26;
                                    r_bus_in_cmd <= '0';
                                    r_bus_in_addr <= r_opB_addr(addr_width-1 downto 0);
                                    r_bus_in_data <= r_opB_data(((c+1)*8)-1 downto (c*8));
                                    if (c=(ds-1)) then
                                        r_bus_in_keep <= '0';
                                    else
                                        r_bus_in_keep <= '1';
                                    end if;
                                    r_stage <= s_WBACK_BUS_1;
                                                                
                                when s_WBACK_BUS_1 =>
                                    r_dbg_instr <= 27;
                                    if (ss_bus_out_drdy='1') then
                                        --  done writing
                                        r_stage <= s_WBACK_BUS_2;
                                    else
                                        --  waiting
                                        r_bus_in_latch <= '1';
                                        r_stage <= s_WBACK_BUS_1;
                                    end if;
                                
                                when s_WBACK_BUS_2 =>
                                    r_dbg_instr <= 28;
                                    if (ss_bus_out_drdy='0') then
                                        if (c=(ds-1)) then
                                            --  it was the last written
                                            c := 0;
                                            r_stage <= s_JMP;
                                        else
                                            --  need to write more
                                            c := c + 1;
                                            r_stage <= s_WBACK_BUS_0;
                                        end if;
                                    else
                                        --  waiting
                                        r_bus_in_latch <= '0';
                                        r_stage <= s_WBACK_BUS_2;
                                    end if;
                            
                                when s_JMP =>
                                    r_dbg_instr <= 29;
                                    --  since this is the very last operation to perform, we must also check for the eventual ISR termination
                                    --  this is signalled with flag status register's bit 2 being HIGH.
                                    if ((r_flag_stat(2)='1') and (r_irq_active='1')) then
                                        --  we need to perform the context switch
                                        r_stage <= s_IRH_3;
                                    else
                                        --  normal operation
                                        --  check on whether to perform the jump
                                        if (r_flag_stat(0)='0') then
                                            --  if the sign flag is 1 or the zero flag is 1
                                            if ((r_flag_stat(5)='1')or(r_flag_stat(6)='1')) then
                                                --  saving the old one and jumping to the requested instruction
                                                r_pc_back <= r_pc;                                                
                                                r_pc <= to_integer(unsigned(r_opC_jump(addr_width-1 downto 0)));
                                            else
                                                --  saving the old one and going to the next instruction in line
                                                r_pc_back <= r_pc;
                                                r_pc <= r_pc + 1;
                                            end if;
                                            --  fetching another instruction
                                            c := 0;
                                            r_stage <= s_IRC; --s_IF_0; --s_DLY;
                                        else
                                            --  must halt the CPU
                                            r_stage <= s_HLT;
                                        end if;
                                    end if;
                                                                
                                when s_IRC =>
                                    --  checking now the presence of an interrupt signal
                                    r_dbg_instr <= 30;
                                    if (ss_sync_0='1') then
                                        --  checking
                                        if (ss_irq_prepare='1') then
                                            --  an interrupt fired, so we need to retrieve the IRQ vector
                                            r_stage <= s_IRH_PRE;
                                        else
                                            --  no interrupts scheduled
                                            r_stage <= s_STAT;
                                        end if;
                                    else
                                        --  waiting for sync
                                        r_stage <= s_IRC;
                                    end if;
                                
                                when s_HLT =>
                                    r_dbg_instr <= 32;
                                    r_HLT <= '1';
                                    if (ss_run='0') then
                                        r_stage <= s_INIT;
                                    else
                                        r_stage <= s_HLT;
                                    end if;
                                
                                --  interrupts
                                when s_IRH_PRE =>
                                    r_dbg_instr <= 200;
                                    if (ss_irq_prepare='0') then
                                        r_irq_vector_ack <= '0';
                                        r_stage <= s_IRH_0;
                                    else
                                        r_irq_vector_ack <= '1';
                                        r_stage <= s_IRH_PRE;
                                    end if;
                                
                                when s_IRH_0 =>
                                    r_dbg_instr <= 201;
                                    --  we need to gather the data from the device, so
                                    if ((ss_sync_0='1') and (ss_irq_vector_drdy='1')) then
                                        isr_file(c) <= ss_irq_vector_bus;
                                        r_stage <= s_IRH_1;
                                    else
                                        --  waiting
                                        r_stage <= s_IRH_0;
                                    end if;
                                
                                when s_IRH_1 => 
                                    r_dbg_instr <= 202;
                                    if (ss_irq_vector_drdy='0') then
                                        r_irq_vector_ack <= '0';
                                        if (ss_irq_vector_done='1') then
                                            --  we've read everything
                                            c := 0;
                                            r_stage <= s_IRH_2;
                                        else
                                            --  still have to read
                                            c := c + 1;
                                            r_stage <= s_IRH_0;
                                        end if;
                                    else
                                        r_irq_vector_ack <= '1';
                                        r_stage <= s_IRH_1;
                                    end if;
                                
                                when s_IRH_2 =>
                                    r_dbg_instr <= 203;
                                    --  after we've read it all, we activate the procedure and we wait for the IRH to lock
                                    if (ss_irq_active_wait='1') then
                                        --  now we can jump to the ISR -> i must save the program counter
                                        r_pc_save <= r_pc;
                                        r_flag_stat_save <= r_flag_stat;
                                        --  an now we have to update it
                                        r_flag_stat(2) <= '0';
                                        r_pc <= to_integer(unsigned(isr_file(0)));
                                        --  we can now start the ISR
                                        r_stage <= s_STAT; --s_IF_0;
                                    else
                                        r_irq_active <= '1';
                                        r_stage <= s_IRH_2;
                                    end if;
                                
                                when s_IRH_3 =>
                                    r_dbg_instr <= 204;
                                     -- we jump here at the end of the ISR, so we need to restore the program counter and also signal the IRH handler
                                    if (ss_irq_active_wait='0') then
                                        --  restoring
                                        r_pc <= r_pc_save;
                                        r_flag_stat <= r_flag_stat_save;
                                        --  resuming program execution
                                        r_stage <= s_STAT; --s_IF_0;
                                    else
                                        r_irq_active <= '0';
                                        r_stage <= s_IRH_3;
                                    end if;
                                                                        
                                when others =>
                                    r_stage <= s_STAT; --s_IF_0;
                            end case;
                        end if;
                    end if;
                end process MAIN;
        
    --  assignments
    dbg_instr <= r_dbg_instr; --to_integer(unsigned(r_acc)); --r_dbg_instr;
    output_port <= to_integer(unsigned(r_acc));
    irq_vector_ack <= r_irq_vector_ack;
    irq_active <= r_irq_active;
    halt <= r_HLT;
    
end Behavioral;
