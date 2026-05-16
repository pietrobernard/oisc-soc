library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

--  programmable interrupt controller
--  each interrupt code is mapped to a specific area of the SRAM where an ISR resides.
--  the isr is a sequence of instructions for the cpu.
--  for instance the UART deevice might trigger an interrupt code x"??" that will make the
--  PIC to order the cpu to jump to the ISR, execute the code and then resume normal execution.
entity cpu_PIC is
    generic (
        n_irq_lines: natural := 8
    );
    port (
        sysClk: in std_logic;
        sysRstb: in std_logic;
        --  interrupt vector
        irq_lines: in std_logic_vector(n_irq_lines-1 downto 0);
        irq_grant: out std_logic_vector(n_irq_lines-1 downto 0);
        --  cpu control signals
        cpu_halt: out std_logic;
        cpu_status: in std_logic
    );
end cpu_PIC;

architecture Behavioral of cpu_PIC is
    signal ss_irq_vector: std_logic_vector(n_irq_lines-1 downto 0);
    signal ss_irq_pres: std_logic;
    signal ss_cpu_status: std_logic;
    type t_SM is (s_INIT, s_IDLE, s_IRQ_0, s_IRQ_1, s_IRQ_2);
    signal r_stage: t_SM := s_INIT;
    
    signal r_cpu_halt: std_logic := '0';
    signal r_irq_grant: std_logic_vector(n_irq_lines-1 downto 0) := (others=>'0');
begin
    --  output signals
    cpu_halt <= r_cpu_halt;
    irq_grant <= r_irq_grant;
    
    SAMP:   process(sysClk)
            begin
                if (falling_edge(sysClk)) then
                    case (r_stage) is
                        when s_INIT =>
                            ss_irq_vector <= (others=>'0');
                        
                        when s_IDLE =>
                            ss_irq_vector <= irq_lines;
                        
                        when others =>
                            null;
                    end case;
                end if;
            end process SAMP;
    
    --  or device
    IRQ_PRESENT:    for i in 0 to (n_irq_lines-1) generate                     
                        ss_irq_pres <= ss_irq_pres or ss_irq_vector(i);
                    end generate IRQ_PRESENT;
                    
    MAIN:   process(sysClk)
                variable idx: natural := 0;
            begin
                if (rising_edge(sysClk)) then
                    case (r_stage) is
                        when s_INIT =>
                            idx := 0;
                            r_stage <= s_IDLE;
                        
                        when s_IDLE =>
                            --  waiting for an event on the interrupt vector
                            idx := 0;
                            if (ss_irq_pres='1') then
                                --  processing an interrupt
                                r_stage <= s_IRQ_0;
                            else
                                r_stage <= s_IDLE;
                            end if;
                    
                        when s_IRQ_0 =>
                            --  checking what to do
                            if (ss_irq_vector(idx)='1') then
                                --  request for interrupt from this line.
                                --  we need to perform the following actions:
                                --  we need to stop the cpu as soon as possible (basically we let the cpu complete the last instruction so that the bus is free)
                                --  we need to tell the device we've granted the interrupt request and we need to read from the device interrupt data buffer to get the
                                --  interrupt service routine pointer and an eventual argument
                                --  when the interrupt service routine completes, the device is signalled and it must drive its interrupt request line low.
                                --  if there are further interrupt requests they are all processed before control is returned to the cpu and normal execution resumes.
                                r_cpu_halt <= '0';
                                r_stage <= s_IRQ_1;
                            else
                                --  going to the next line
                                idx := idx + 1;
                                r_stage <= s_IRQ_0;
                            end if;
                        
                        when s_IRQ_1 =>
                            --  waiting for the cpu to stop what is doing
                            if (ss_cpu_status='0') then
                                --  the cpu has stop, signalling the remote device it can proceed with sending us the data
                                r_irq_grant(idx) <= '1';
                                r_stage <= s_IRQ_2;
                            else
                                --  waiting for the cpu
                                r_stage <= s_IRQ_1;
                            end if;
                    
                        when s_IRQ_2 =>
                            --  must now wait for the remote device to contact us with the data regarding its interrupt
                            r_stage <= s_IRQ_2;
                            
                            
                    end case;
                end if;
            end process MAIN;
    
end Behavioral;
