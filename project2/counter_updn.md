```vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity updncounter_v2 is
	generic(
		upper : integer := 9; 
		lower : integer := 0
	);
	port(
		clk, rst : in  STD_LOGIC; 
		dir      : in  STD_LOGIC;
		Q        : out STD_LOGIC_VECTOR(3 downto 0);
		P        : out STD_LOGIC_VECTOR(3 downto 0)
	);
end updncounter_v2;
	
architecture Behavioral of updncounter_v2 is

	signal div_reg  : unsigned(26 downto 0) := (others => '0');
	signal slow_clk : std_logic;

    
	signal Qn : integer := lower;
	signal Pn : integer := lower;
begin


	process(clk)
	begin
		if rising_edge(clk) then
			div_reg <= div_reg + 1;
		end if;
	end process;
	

	slow_clk <= div_reg(26);


	counter1 : process(slow_clk, rst)
	begin
		if rst = '1' then
			Qn <= lower;
		elsif rising_edge(slow_clk) then
			if dir = '1' then
				if Qn >= upper then
					Qn <= lower;
				else
					Qn <= Qn + 1;
				end if;
			else
				if Qn <= lower then
					Qn <= upper;
				else 
					Qn <= Qn - 1;
				end if;
			end if;
		end if;
	end process;

	counter2 : process(slow_clk, rst)
	begin
		if rst = '1' then
			Pn <= upper;
		elsif rising_edge(slow_clk) then
			if dir = '1' then
				if Pn <= lower then
					Pn <= upper;
				else
					Pn <= Pn - 1;
				end if;
			else
				if Pn >= upper then
					Pn <= lower;
				else 
					Pn <= Pn + 1;
				end if;
			end if;
		end if;
	end process;

	Q <= std_logic_vector(to_unsigned(Qn, Q'length));
	P <= std_logic_vector(to_unsigned(Pn, P'length));

end Behavioral;
```
## 波形圖
<img width="1577" height="784" alt="image" src="https://github.com/user-attachments/assets/297ad81a-9ba8-4a6e-ad95-3efd452d758c" />

##架構圖
<img width="1049" height="440" alt="image" src="https://github.com/user-attachments/assets/be27764b-65ab-4e8e-bdb7-e8cf8d31c617" />
