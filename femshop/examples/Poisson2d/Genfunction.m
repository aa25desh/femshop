%This file was generated by Femshop.

%{
Generated functions
%}
genfunction_0_fun = @(x,y,z,t) (sin(3*pi*x));
genfunction_0 = mesh.evaluate(genfunction_0_fun, config.basis_order_min, 'gll');
genfunction_1_fun = @(x,y,z,t) (-2*pi*pi*sin(pi*x)*sin(pi*y));
genfunction_1 = mesh.evaluate(genfunction_1_fun, config.basis_order_min, 'gll');
u = 'u';
f = genfunction_1;