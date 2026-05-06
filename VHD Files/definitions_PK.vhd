library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

package definitions_PK is
    -- Defining constants 
    constant DATA_WIDTH : natural := 8;
    constant REG_WIDTH : natural := 16;
    constant MAX_BUFF_LENGTH : natural := 512;
    
    -- Function for calculating log base-2
    impure function clogb2 (depth: in natural) return integer;
end definitions_PK;

package body definitions_PK is
    -- The following function calculates number of bits 
    -- required for addressing "depth" number of entries 
    impure function clogb2(depth : natural) return integer is
        variable temp    : integer := depth;
        variable ret_val : integer := 0;
    begin
        while (temp > 1) loop
            ret_val := ret_val + 1;
            temp := temp / 2;
        end loop;
        return ret_val;
    end function;
end package body definitions_PK;
