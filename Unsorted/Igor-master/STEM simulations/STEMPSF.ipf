#pragma rtGlobals=1		// Use modern global access method.

// Functions to calculate STEM point spread function (PSF); STEM PSF
// is the probe profile
//
// 01-06-10  rewritten to support full coherent aberrations generated by CEOS software on the Titan
//                and to use CEOS notation for aberrations (yuck).  pmv
// 02-05-10  added effects of a Gaussian source function
//
// Aberration parameters are:
//	C1, defocus, in nm
//	A1, 2-fold astigmatism, in nm
//	A2, 3-fold astigmatism, in nm
//	B2, axial coma, in nm
//	C3, primary spherical aberration, in um
//	A3, 4-fold astigmasitm, in um
//	S3, star aberration, in um
//	A4, 5-fold astigmatism, in um
//	D4, 3-lobe aberration, in um
//	B4, axial coma, in um
//	C5, 5th order spherical aberration, in mm
//	A5, 5th order spherical aberration, in mm
//
// Aberrations must be specified in a 12x2 wave.  The first column is the aberration coefficient, the
// second is the rotation angle.  Rotation angles for axially symmetric aberrations (C1, C3, C5) are
// ignored.  Aberrations can be set to zero.
//
// Other required parameters are:
// Cc = chromatic aberration coefficient in mm
// dE = beam energy spread (FWHM) in eV
// ds = source function FWHM.  Source is assumed to be Gaussian
// keV = beam energy in kV
// ap = condenser aperture in mrad
// nk = number of k points to integrate over in calculating the PSF
//
// In the function names "Coh" means coherent, without chromatic aberration.  "Incoh" means incoherent,
// or with chromatic aberration.  Neither includes spatial incoherence (source size).

// calculates 3D STEM prove wave field.  feed it the defocus
// with the probe focused at the entrance surface and it'll recenter
// the probe in the volume properly.
function STEMpsf3DSym(psf3D, C5, Cs, df, Cc, dE, keV, ap)
	wave psf3D
	variable C5, Cs, df, Cc, dE, keV, ap
	
	variable nx = DimSize(psf3d, 0)
	variable ny = DimSize(psf3d, 1)
	variable nz = DimSize(psf3d, 2)
	
	Make/O/N=( max(nx, ny)*1.5, nz ) rz
	variable rmax, xmax, ymax
	xmax = max( abs(DimOffset(psf3D, 0)), abs(DimOffset(psf3D, 0) + nx*DimDelta(psf3d, 0)) )
	ymax = max( abs(DimOffset(psf3D, 1)), abs(DimOffset(psf3D, 1) + ny*DimDelta(psf3d, 1)) )
	rmax = 1.05*sqrt(xmax^2 + ymax^2)
	SetScale/I x 0, rmax, "", rz
	SetScale/P y DimOffSet(psf3d, 2), DimDelta(psf3D, 2), "", rz
	
	df -= nz*DimDelta(psf3D, 2) / 2
	//printf "df = %g\r", df
	//stempsf3Drz(rz, C5, Cs, df, Cc, dE, keV, ap)
	
	psf3D = rz(sqrt(x^2+y^2))(z)
	Killwaves rz
end


function STEMPSF1DCoh(aber, keV, ap, nk)
	wave aber
	variable keV, ap, nk
	
	STEMPSF2DCoh(aber, keV, ap, nk)
	wave probe2DCoh = $"probe2DCoh"
	
	AnnularAverage(probe2DCoh, 0.0, 0.0, 1)
	Duplicate/O annular_av, probe1DCoh
	Killwaves annular_av, probe2DCoh
	
end

function STEMPSF1DIncoh(aber, keV, Cc, dE, ds, ap, nk)
	wave aber
	variable keV, Cc, dE, ds, ap, nk
	
	STEMPSF2DIncoh(aber, keV, Cc, dE, ds, ap, nk)
	wave probe2DIncoh = $"probe2DIncoh"
	
	AnnularAverage(probe2DIncoh, 0.0, 0.0, 1)
	Duplicate annular_av probe1DIncoh
	Killwaves annular_av, probe2DIncoh
	
end

function STEMPSF2DCoh(aber, keV, ap, nk)
	wave aber
	variable keV, ap, nk
	
	variable kmax = 0.001*ap / wavlen(keV)
	
	ChiPhase2D(aber, keV, ap, nk/10)
	wave phase = $"phase"

	// need to pad the phase with zeros here.
	Make/C/O/N=(nk, nk) probe2DCoh
	SetScale/I x -20*kmax, 40*kmax, "", probe2DCoh
	SetScale/I y -20*kmax, 40*kmax, "", probe2DCoh
	probe2DCoh = ( (x^2 + y^2 < kmax^2) ?  p2rect(cmplx(1, phase(x)(y)))  : cmplx(0, 0))

	FFT probe2DCoh
	probe2DCoh = cmplx(magsqr(probe2DCoh), 0)
	Redimension/R probe2DCoh
	
	wavestats/Q probe2DCoh
	probe2DCoh /= V_Sum
	
	Killwaves phase
	
end

function STEMPSF2DIncoh(aber, keV, Cc, dE, ds, ap, nk)
	wave aber
	variable keV, cC, dE, ds, ap, nk
	
	variable kmax = 0.001*ap / wavlen(keV)
	
	if(Cc != 0.0 && dE != 0.0)
	
		ChromaticDefocusDistribution(Cc, dE, keV, ap)
		wave defocus_distribution = $"defocus_distribution"
		variable i, start_df
	
		start_df = aber[0][0]
	
		printf "Total focus steps: %d\r", numpnts(defocus_distribution)
		printf "Working on step: "
		for(i=0; i<numpnts(defocus_distribution); i+=1)
			if(!mod(i, 5))
				printf " %d . .", i
			endif
			aber[0][0] = start_df + pnt2x(defocus_distribution, i)
			STEMPSF2DCoh(aber, keV, ap, nk)
			wave probe2DCoh = $"probe2DCoh"
			if(i==0)
				Duplicate/O probe2DCoh probe2DIncoh
				probe2DIncoh *= defocus_distribution[0]
			else
				probe2DIncoh += defocus_distribution[i]*probe2DCoh
			endif
		endfor
		printf "\r"
	
		probe2DIncoh /= sum(defocus_distribution, -inf, inf)
	
		aber[0][0] = start_df
		Killwaves defocus_distribution

	else
		STEMPSF2DCoh(aber, keV, ap, nk)
		wave probe2DCoh = $"probe2DCoh"
		Duplicate/O probe2Dcoh probe2DIncoh
	endif

	if(ds != 0)
		variable fds = ds / (2*sqrt(2*ln(2)))	// real-space standard deviation for Gaussian with FWHM ds
		fds = 1/(2*Pi*fds)	// FT standard deviation
		//printf "fds = %g\r", fds
		Redimension/C probe2DIncoh
		wave/C probe2DSS = $"probe2DIncoh"
		FFT probe2DSS
		probe2DSS *= cmplx(Gauss(x, 0.0, fds, y, 0.0, fds), 0.0)
		IFFT/C probe2DSS
		//probe2DSS = cmplx(sqrt(magsqr(probe2DSS)), 0)
		Redimension/R probe2DSS
		wavestats/Q probe2DSS
		probe2DSS /= V_sum
		SetScale/p x dimoffset(probe2dcoh, 0), dimdelta(probe2dcoh, 0), "", probe2dIncoh
		SetScale/P y dimoffset(probe2dcoh, 1), dimdelta(probe2dcoh, 1), "", probe2dincoh
	endif

	Killwaves probe2DCoh

end
	
function ChiPhase1D(aber, keV, ap, nk)
	wave aber
	variable keV, ap, nk
	
	SwitchtoAngstroms(aber)

	variable wl = wavlen(keV)
	variable kmax= 0.001*ap / wl // maximum k through aperture
	
	Make/O/D/N=(nk) phase
	SetScale/I x 0, kmax, "", phase
	variable w1 = 0.5*aber[4][0]*wl^3
	variable w2 = aber[0][0]*wl
	variable w3 = wl^5*aber[10][0]/3
	phase = Pi*(w3*x^4 + w1*x^2 - w2)*x^2
	
end


function ChiPhase2D(aber, keV, ap, nk)
	wave aber
	variable keV, ap, nk
	
	SwitchToAngstroms(aber)
	
	variable wl = wavlen(keV)
	variable kmax = (0.001*ap / wl)  // maximum k through aperture
	variable i, j
	
	Make/O/D/N=(nk, nk, 12) astack
	SetScale/I x -2*kmax, 2*kmax, "", astack
	SetScale/I y -2*kmax, 2*kmax, "", astack
	
	// Evaluate the phase shifts from the various aberrations
	astack[][][0] = (1/2)*wl*aber[0][0]*(x^2 + y^2)	//	C1, defocus
	astack[][][1] = (1/2)*wl*aber[1][0]*(x^2 - y^2) 	//	A1, 2-fold astigmatism
	astack[][][2] = (1/3)*wl^2*aber[2][0]*(x^3 - 3*x*y^2)	//	A2, 3-fold astigmatism
	astack[][][3] = wl^2*aber[3][0]*(x^3 + x*y^2)	//	B2, axial coma
	astack[][][4] = (1/4)*wl^3*aber[4][0]*(x^4 + 2*x^2*y^2 + y^4)	//	C3, primary spherical aberration
	astack[][][5] = (1/4)*wl^3*aber[5][0]*(x^4 - 6*x^2*y^2 + y^4)	//	A3, 4-fold astigmasitm
	astack[][][6] = wl^3*aber[6][0]*(x^4 - y^4)	//	S3, star aberration
	astack[][][7] = (1/5)*wl^4*aber[7][0]*(x^5 - 10*x^3*y^2 + 5*x*y^4)	//	A4, 5-fold astigmatism
	astack[][][8] = wl^4*aber[8][0]*(x^5 - 2*x^3*y^2 - 3*x*y^4)	//	D4, 3-lobe aberration
	astack[][][9] = wl^4*aber[9][0]*(x^5 + 2*x^3*y^2 + x*y^4)	//	B4, axial coma
	astack[][][10] = (1/6)*wl^5*aber[10][0]*(x^6 + 3*x^4*y^2 + 3*x^2*y^4 + y^6)	//	C5, 5th order spherical aberration
	astack[][][11] = (1/6)*wl^5*aber[11][0]*(x^6 - 15*x^4*y^2 + 15*x^2*y^4 - y^6)	//	A5, 5th order spherical aberration

	// rotate the phase shifts of the non-centrosymmetric aberrations
	for(i=0; i<12; i+=1)
		if( aber[i][1] != 0.0) 
			ImageTransform/P=(i) getplane astack
			wave aphase = $"M_ImagePlane"
			ImageRotate/E=0/O/A=(aber[i][1]) aphase
			SetScale/P x -DimSize(aphase, 0)*DimDelta(astack, 0) / 2, DimDelta(astack, 0), "", aphase
			SetScale/P y -DimSize(aphase, 1)*DimDelta(astack, 1) / 2, DimDelta(astack, 0), "", aphase
			astack[][][i] = aphase(x)(y)
			Killwaves M_ImagePlane
		endif
	endfor

	// sum all the aberration contributions
	MatrixOp/O phase = 2*Pi*sumbeams(astack)
	SetScale/I x -2*kmax, 2*kmax, "", phase
	SetScale/I y -2*kmax, 2*kmax, "", phase

	//Killwaves astack
	
end
	
//calculate electron wavelength in Angstroms given the energy in keV.
function wavlen(keV)
	variable keV
	
	return 12.3986 / sqrt( (2*511.0 + keV) * keV) 
end

// function to switch aberrations wave into Angstroms instead of natural units
function SwitchToAngstroms(aber)
	wave aber
	
	if(NumberByKey( "units", note(aber), "=") == 1)
		return 0
	endif
		
	//C1, A1, A3, B2, all start in nm
	aber[0,3][0] = 10*aber[p][0]

	// C3, A3, S3, A4, D4, B4 start in um
	aber[4,9][0] = 1e4*aber[p][0]
	
	// C5, A5 in mm
	aber[10,11][0] = 1e7*aber[p][0]
	
	Note/K aber, ReplaceNumberByKey("units", note(aber), 1, "=")
	
end

function ChromaticDefocusDistribution(Cc, dE, keV, ap)
	variable Cc, dE, keV, ap

	Cc *= 1e7  // mm to Angstroms
	variable df_phase_max = 2*Pi / 50  // maximum phase step at the aperture edge due to chromatic aberration
	variable kmax = 0.001*ap/wavlen(keV)
	variable ndf

	// defocus range and form from Reimer
	variable H = (Cc*dE /(1e3*keV)*( (1+keV/511)/(1+kev/1022) )
	variable N = (2*sqrt(ln(2)) / (sqrt(Pi)*H))
	variable df_range = 2.5*H
	ndf = ceil(df_range * wavlen(keV) * kmax^2 / df_phase_max)
	ndf = (ndf < 31 ? 31 : ndf)
	ndf = (!mod(ndf, 2) ? ndf+1 : ndf)
	Make/O/N=(ndf) defocus_distribution
	SetScale/I x -df_range, df_range, "", defocus_distribution
	
	defocus_distribution = N*exp( -ln(2) * (2*x / H)^2 )
	//if((1.0 - area(defocus_dist, -inf, inf)) > 1e-3)
		//	printf "Area of the defocus distribution is %g.  Probably too few points in defocus distribution.\r", 1.0 - area(defocus_dist, -inf, inf)
	//endif

end


// Does a rotational average about the specified point, xx and yy with a bin width of strip_width.
// xx and yy are in real units, taking into account the wave scaling.  strip_width is in pixels.
// average is placed the wave annular_av, and the function returns the number of pixels in 
// the annular average.
function AnnularAverage(dat, xx, yy, strip_width)
	wave dat
	variable xx, yy, strip_width
	
	// translate center point from wave scaling units to pixels
	variable cp = round( ((xx - DimOffset(dat, 0))/DimDelta(dat, 0)) )
	variable cq = round( ((yy - DimOffSet(dat, 1))/DimDelta(dat, 1)) )
	
	// find the radius of the annular average accounting for strip_width
	variable sx = DimSize(dat, 0)
	variable sy = DimSize(dat, 1)
	variable rad = max( max(cp, abs(cp-sx)), max(cq, abs(cq-sy)) )
	rad = floor( rad / strip_width)
	
	// make the output and pixel-counting waves
	Make/O/N=(rad) annular_av, npix
	SetScale/P x 0, DimDelta(dat, 0)*strip_width, "", annular_av
	annular_av = 0
	npix = 0
	
	
	// perform the annular average
	variable i, j, rpix
	for(i=0; i<sx; i+=1)
		for(j=0; j<sy; j+=1)
			if(!NumType(dat[i][j]))
				rpix = round( sqrt( (i-cp)^2 + (j-cq)^2) / strip_width )
				if(rpix < rad)
					annular_av[rpix] += dat[i][j]
					npix[rpix] += 1
				endif
			endif
		endfor
	endfor
	
	// normalize by the number of pixels in each bin
	annular_av /= npix

	// clean up temporary waves
	Killwaves/Z npix

	// return the radius of the annular average
	return rad	
end


