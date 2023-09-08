import os
import sys

import numpy
import numpy.ma as ma

import netCDF4 

def enthalpy_snow(Tsfcn, vsnon):
  #debug: 
  print("in enthalpy_snow ",Tsfcn.max(), Tsfcn.min(), vsnon.max(), vsnon.min())
  rho_snow =  330.0
  cp       = 2160.0
  L        = 3.34e5
  #enthalpy = -rho_snow*(cp*Tsfcn + L)*vsnon
  enthalpy = Tsfcn
  print("a1 ",enthalpy.max(), enthalpy.min() )
  #enthalpy *= cp
  #enthalpy += L
  enthalpy = (Tsfcn*cp + L)
  print("a2 ",enthalpy.max(), enthalpy.min() )
  enthalpy *= -rho_snow
  enthalpy *= vsnon
  #debug: print(enthalpy)
  print("a4 ",enthalpy.max(), enthalpy.min() )
  return enthalpy

stresses = ["uvel", "vvel", "strocnxT", "strocnyT", "stressp_1", "stressp_2", "stressp_3", "stressp_4", "stressm_1", "stressm_2", "stressm_3", "stressm_4", "stress12_1", "stress12_2", "stress12_3", "stress12_4"]
#dynamics:
dynam = [ "uvel", "vvel", "stressp_1", "stressp_2", "stressp_3", "stressp_4", "stressm_1", "stressm_2", "stressm_3", "stressm_4", "stress12_1", "stress12_2", "stress12_3", "stress12_4" ]

parms3 = [ "aicen", "vicen", "vsnon", "Tsfcn", "iage", "FY", "alvl", "vlvl", "apnd", "hpnd", "ipnd", "dhs", "ffrac", "fbrn", "first_ice", "sice001", "qice001", "sice002", "qice002", "sice003", "qice003", "sice004", "qice004", "sice005", "qice005", "sice006", "qice006", "sice007", "qice007", "qsno001" ]


  

# For reading: -------------------------------------------
model_in  = netCDF4.Dataset(sys.argv[1], 'r', format="NETCDF4")
model_out = netCDF4.Dataset(sys.argv[2], "w", format="NETCDF4")

#After https://stackoverflow.com/questions/13936563/copy-netcdf-file-using-python
# Create the dimensions of the file
for name, dim in model_in.dimensions.items():
    #debug: print("debug -- dimensions: ",name, dim, flush=True)
    model_out.createDimension(name, len(dim) if not dim.isunlimited() else None)

# Copy the global attributes
model_out.setncatts({a:model_in.getncattr(a) for a in model_in.ncattrs()})

# Create the variables in the file
for name, var in model_in.variables.items():
    model_out.createVariable(name, var.dtype, var.dimensions)
    #debug: print(name, var.dtype, var.dimensions, flush=True)

    # Copy the variable attributes
    model_out.variables[name].setncatts({a:var.getncattr(a) for a in var.ncattrs()})

    # Copy the variables values (as 'f4' eventually)
    model_out.variables[name][:] = model_in.variables[name][:]

    #debug: if (name in parms3):
    #debug:    print(name, model_out.variables[name][:].max(), model_out.variables[name][:].min() )
    #debug:    for i in range (0,5):
    #debug:        print(i, name,  model_out.variables[name][i].max(), model_out.variables[name][i].min() )

    # Step with some editing. Stresses are actually unused (confirmed by expt)
    if name in stresses:
      model_out.variables[name][:] = 0.0 

    if (name == "vsnon"):
      print(var.dimensions, dim)
      vsnon = numpy.zeros((5,116,100))
      model_out.variables[name][:] = 0.0

    # To trim out excessively thin or low concentration ice, 
    #   save ai and hi aside, then reprocess prior to write out
    if (name == 'aicen' ):
      tmp_aice = model_out.variables['aicen'][:] 
    if (name == 'vicen' ):
      tmp_vice = model_out.variables['vicen'][:] 


    if (name == "qsno001"):
        t = model_in.variables["Tsfcn"][:]
        #v = model_in.variables["vsnon"][:]
        v = vsnon
        x = enthalpy_snow(t, v)
        #print(x)
        model_out.variables["qsno001"][:] = x

# Touch up hi and aice -- remove very low concentrations and/or thicknesses:
aice = tmp_aice[0]
hi   = tmp_vice[0]
for k in range (1, 5):
  aice += tmp_aice[k] # ncat, nj, ni
  hi   += tmp_vice[k]

print("ai, hi: ",aice.max(), aice.min(), hi.max(), hi.min() )

mask1 = ma.masked_array(aice > 0.)
mask2 = ma.masked_array(hi > 0.)
mask1 = ma.logical_and(mask1, aice < 0.01)
mask2 = ma.logical_and(mask2, hi < 0.01)
mask2 = ma.logical_or(mask2, mask1)
indices = mask2.nonzero()
for k in range(0, len(indices[0])):
  i = indices[1][k]
  j = indices[0][k]
  tmp_aice[:,j,i] = 0.0
  tmp_vice[:,j,i] = 0.0
  model_out.variables['qice001'][:,j,i]  = 0.0
  model_out.variables['qice002'][:,j,i]  = 0.0
  model_out.variables['qice003'][:,j,i]  = 0.0
  model_out.variables['qice004'][:,j,i]  = 0.0
  model_out.variables['qice005'][:,j,i]  = 0.0
  model_out.variables['qice006'][:,j,i]  = 0.0
  model_out.variables['qice007'][:,j,i]  = 0.0


model_out.variables['aicen'] = tmp_aice
model_out.variables['vicen'] = tmp_vice
#model_out.variables['qice001'] = qice001
#model_out.variables['qice002'] = qice002
#model_out.variables['qice003'] = qice003
#model_out.variables['qice004'] = qice004
#model_out.variables['qice005'] = qice005
#model_out.variables['qice006'] = qice006
#model_out.variables['qice007'] = qice007



# Save the file
model_out.close()

