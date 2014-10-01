-- BrainF* interpreter
-- Version: 0.0.00
-- Author:  Ronald Landheer-Cieslak
-- Copyright (c) 2014  Vlinder Software
-- License: http://opensource.org/licenses/CDDL-1.0
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity BrainF is
    generic(
          MAX_INSTRUCTION_COUNT : positive := 65536
        ; MEMORY_SIZE : positive := 65536
        );
    port(
          resetN : in std_logic
        ; clock : in std_logic
        
        ; load_instructions : in std_logic
        ; instruction_octet : in std_logic_vector(7 downto 0)
        ; ack_instruction : out std_logic := '0'
        ; program_full : out std_logic := '0'
        
        ; read_memory : in std_logic
        ; memory_byte : out std_logic_vector(7 downto 0) := (others => '0')
        ; memory_byte_ready : out std_logic := '0'
        ; memory_byte_read_ack : in std_logic
        
        ; done : out std_logic := '0'
        );
end entity;
architecture behavior of BrainF is
    type Instruction is (dot, plus, minus, advance, back_up, begin_loop, end_loop);
    type Instructions is array(0 to (MAX_INSTRUCTION_COUNT - 1)) of Instruction;
    type Pipeline is array(0 to 1) of Instruction;
    subtype IPointer is integer range 0 to MAX_INSTRUCTION_COUNT;
    type InterpreterState is (execute_instruction, fetch_instruction);
    subtype NestCount is integer range 0 to MAX_INSTRUCTION_COUNT - 1;
    
    type Memory is array(0 to (MEMORY_SIZE - 1)) of std_logic_vector(7 downto 0);
    subtype Pointer is integer range 0 to (MEMORY_SIZE - 1);
    
    function toInstruction(i : std_logic_vector(7 downto 0)) return Instruction is
    begin
        case i is
        when x"2B" => return plus;
        when x"2D" => return minus;
        when x"3E" => return advance;
        when x"3C" => return back_up;
        when x"5B" => return begin_loop;
        when x"5D" => return end_loop;
        when others => return dot;
        end case;
    end toInstruction;
    function increment(b : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        if b = x"FF" then
            return x"00";
        else
            return std_logic_vector(unsigned(b) + 1);
        end if;
    end increment;
    function decrement(b : std_logic_vector(7 downto 0)) return std_logic_vector is
    begin
        if b = x"00" then
            return x"FF";
        else
            return std_logic_vector(unsigned(b) - 1);
        end if;
    end decrement;
    
    -- produced by p_interpret
    signal ptr                          : Pointer := 0;
    signal mem                          : Memory := (others => (others => '0'));
    signal stalled                      : std_logic := '0'; -- signals it's going forward in a loop. The p_fetch process will continue 
                                                            -- fetching until it finds the corresponding end-of-loop and puts that in pipe(0) at that time. 
    -- produced by p_fetch
    signal pipe                         : Pipeline := (others => dot);
    signal iptr                         : IPointer := 0;
    signal nest_count                   : NestCount := 0;
    signal expect_stall                 : std_logic := '0';
    signal should_back_up_on_stall      : std_logic := '0'; -- set if we expect a stall on an end_loop instruction
    -- produced by p_loadInstructions
    signal program                      : Instructions := (others => dot);
    signal prev_load_instructions       : std_logic := '0';
    signal instruction_step             : std_logic := '0';
    signal iwptr                        : IPointer := 0;
    signal internal_program_full        : std_logic := '0';
    -- produced by p_readMemory
    signal prev_memory_byte_read_ack    : std_logic := '0';
    signal prev_read_memory             : std_logic := '0';
begin
    p_interpret : process(resetN, clock, load_instructions, read_memory)
    begin
        if resetN = '0' or load_instructions = '1' then
            ptr <= 0;
            mem <= (others => (others => '0'));
            stalled <= '0';
        elsif load_instructions = '0' and read_memory = '0' then
            if rising_edge(clock) then
                case pipe(0) is
                when dot =>
                    null;
                when plus =>
                    mem(ptr) <= increment(mem(ptr));
                when minus =>
                    mem(ptr) <= decrement(mem(ptr));
                when advance =>
                    if ptr = MEMORY_SIZE - 1 then
                        ptr <= 0;
                    else 
                        ptr <= ptr + 1;
                    end if;
                when back_up =>
                    if ptr = 0 then
                        ptr <= MEMORY_SIZE - 1;
                    else
                        ptr <= ptr - 1;
                    end if;
                when begin_loop => 
                    if mem(ptr) = x"00" then
                        stalled <= '1';
                    else
                        stalled <= '0';
                    end if;
                when end_loop =>
                    if mem(ptr) /= x"00" then
                        stalled <= '1';
                    else
                        stalled <= '0';
                    end if;
                end case;
            end if;
        end if;
    end process;
    
    p_fetch : process(resetN, clock, load_instructions, read_memory)
        variable done_skipping : boolean := False;
    begin
        if resetN = '0' or load_instructions = '1' then
            pipe <= (others => dot);
            iptr <= 0;
            nest_count <= 0;
            done <= '0';
            expect_stall <= '0';
            should_back_up_on_stall <= '0';
            done_skipping := False;
        elsif load_instructions ='0' and read_memory = '0' then
            if rising_edge(clock) then
                -- if pipe(1) contains a begin_loop instruction, the p_interpret process may start stalling as soon as 
                -- it sees it, which we will only know one (extra) clock cycle afterwards. In that case, we don't want
                -- to give it the next instruction unless we know it has had time to take a decision. Hence, if there's
                -- a begin_loop instruction in pipe(1) we set the expect_stall flag. If there's a begin_loop in pipe(0)
                -- and the expect_stall flag is set, we clear the flag and do nothing else. If the flag is not set, we
                -- check whether the stalled signal is raised and, if so, start searching for the end of the loop. If
                -- it's not set, we continue as normal.
                -- if pipe(1) contains an end_loop instruction, p_interpret may also stall but if it does, we need to 
                -- start backing up. When pipe(1) contains an instruction, the instruction pointer (iptr) already 
                -- points one past the instruction, because we're getting ready to read the next instruction into 
                -- pipe(1). Hence, while we can anticipate our not stalling (and therefore load the next instruction 
                -- into pipe(1) regardless) we have to make sure that if we do stall, we start by backing up the 
                -- instruction pointer twice (or not count the end_loop instruction as nesting).
                if (pipe(1) = begin_loop or pipe(1) = end_loop) and stalled /= '1' and expect_stall = '0' then
                    expect_stall <= '1';
                    done_skipping := False;
                    if pipe(1) = end_loop then
                        should_back_up_on_stall <= '1';
                    else
                        should_back_up_on_stall <= '0';
                    end if;
                end if;
                if (pipe(0) = begin_loop or pipe(0) = end_loop) and expect_stall = '1' then
                    expect_stall <= '0';
                else
                    if stalled = '0' then
                        pipe(0) <= pipe(1);
                    elsif stalled = '1' and nest_count = 0 and pipe(0) = begin_loop and pipe(1) = end_loop then
                        -- we're done skipping over the loop!
                        pipe(0) <= pipe(1);
                    elsif stalled = '1' and nest_count = 0 and pipe(0) = end_loop and pipe(1) = begin_loop and should_back_up_on_stall = '0' then
                        -- we are done backing up!
                        pipe(0) <= pipe(1);
                        iptr <= iptr + 2;
                        done_skipping := True;
                    elsif stalled = '1' and pipe(0) = pipe(1) and not done_skipping then
                        nest_count <= nest_count + 1;
                    elsif stalled = '1' and nest_count /= 0 and ((pipe(0) = begin_loop and pipe(1) = end_loop) or (pipe(0) = end_loop and pipe(1) = begin_loop)) then
                        nest_count <= nest_count - 1;
                    end if;
                    if stalled = '0' or (stalled = '1' and pipe(0) = begin_loop) then
                        if iptr = MAX_INSTRUCTION_COUNT then
                            pipe(1) <= dot;
                            done <= '1';
                        else
                            pipe(1) <= program(iptr);
                            done <= '0';
                        end if;
                        if iptr /= MAX_INSTRUCTION_COUNT then
                            iptr <= iptr + 1;
                        end if;
                    elsif not done_skipping then
                        assert stalled = '1' and pipe(0) = end_loop report "Unexpected stall!" severity failure;
                        if should_back_up_on_stall = '1' then
                            assert iptr >= 3 report "Stalled with an invalid instruction pointer!" severity failure;
                            pipe(1) <= program(iptr - 3);
                            iptr <= iptr - 3;
                            should_back_up_on_stall <= '0';
                        else
                            -- this is where we start backing up
                            pipe(1) <= program(iptr);
                            done <= '0';
                            if iptr /= 0 then
                                iptr <= iptr - 1;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    p_loadInstructions : process(clock, resetN)
    begin
        if resetN = '0' then
            program <= (others => dot);
            prev_load_instructions <= '0';
            instruction_step <= '0';
            iwptr <= 0;
            internal_program_full <= '0';
        else
            if rising_edge(clock) then
                if prev_load_instructions = '0' and load_instructions ='1' then
                    program <= (others => dot);
                    iwptr <= 0;
                    instruction_step <= '0';
                    internal_program_full <= '0';
                elsif prev_load_instructions = '1' and load_instructions ='1' then
                    if instruction_step = '0' then
                        if iwptr < MAX_INSTRUCTION_COUNT then
                            program(iwptr) <= toInstruction(instruction_octet);
                            iwptr <= iwptr + 1;
                        else
                            internal_program_full <= '1';
                        end if;
                    end if;
                
                    instruction_step <= not instruction_step and not internal_program_full;
                else
                    iwptr <= 0;
                    instruction_step <= '0';
                end if;
                prev_load_instructions <= load_instructions;
            end if;
        end if;
    end process;
    ack_instruction <= instruction_step;
    program_full <= internal_program_full;
    
    p_readMemory : process(clock, resetN, read_memory)
        variable rptr : integer range 0 to MEMORY_SIZE := 0;
    begin
        if resetN = '0' or read_memory = '0' then
            rptr := 0;
            memory_byte <= (others => '0');
            memory_byte_ready <= '0';
        else
            if rising_edge(clock) then
                if read_memory = '1' then
                    if prev_read_memory = '0' then
                        memory_byte <= mem(0);
                        memory_byte_ready <= '1';
                        rptr := 1;
                    else
                        if prev_memory_byte_read_ack = '0' and memory_byte_read_ack = '1' then
                            if rptr /= MEMORY_SIZE then
                                memory_byte <= mem(rptr);
                                rptr := rptr + 1;
                            else
                                memory_byte_ready <= '0';
                            end if;
                        end if;
                    end if;
                    prev_memory_byte_read_ack <= memory_byte_read_ack;
                end if;
                prev_read_memory <= read_memory;
            end if;
        end if;
    end process;
end behavior;
