#include <math.h>
#include "GMMInvert.h"
#include "GMMMemoryUtility.h"

static int G_ludcmp(double **a, int n, int *indx, double *d);
static void G_lubksb(double **a, int n, int *indx, double b[]);


#define TINY 1.0e-20;

/* inverts a matrix of arbitrary size input as a 2D array. */ 
int invert( double **a, int n ) {
    /* 'a' input/output matrix */
    /* 'n' dimension */
    int  status;
    double  d;

    int *indx = G_alloc_ivector((size_t)n);
    double  **y = G_alloc_matrix((size_t)n, (size_t)n);
    double *col = G_alloc_vector((size_t)n);

    status = G_ludcmp(a, n, indx, &d);
    if( status ) {
        for( int j = 0; j < n; j++ ) {
            for( int i = 0; i < n; i++ ) {
                col[i] = 0.0;
            }
            col[j] = 1.0;
            G_lubksb(a,n,indx,col);
            for( int i = 0; i < n; i++ ) {
                y[i][j] = col[i];
            }
        }

        for( int i = 0; i < n; i++ ) {
            for( int j = 0; j < n; j++) {
                a[i][j] = y[i][j];
            }
        }
    }

    G_free_ivector(indx);
    G_free_matrix(y);
    G_free_vector(col);

    return(status);
}


/* From Numerical Recipies in C */

static int G_ludcmp(double **a, int n, int *indx, double *d) {
    int imax = 0;
    double big, dum, sum, temp;
    double *vv;

    vv = G_alloc_vector((size_t)n);
    *d = 1.0;
    for ( int i = 0; i < n; i++ ) {
        big = 0.0;
        for ( int j = 0; j < n; j++ ) {
            if ((temp = fabs(a[i][j])) > big) {
               big = temp;
            }
        }
        if ( big == 0.0 ) {
            return 0; /* Singular matrix  */
        }
        vv[i] = 1.0 / big;
    }
    for ( int j = 0; j < n; j++) {
        for ( int i = 0; i < j; i++) {
            sum = a[i][j];
            for ( int k = 0; k < i; k++ ) {
                sum -= a[i][k] * a[k][j];
            }
            a[i][j] = sum;
        }
        big = 0.0;
        for ( int i = j; i < n; i++ ) {
            sum = a[i][j];
            for ( int k = 0; k < j; k++ ) {
                sum -= a[i][k] * a[k][j];
            }
            a[i][j] = sum;
            if ( (dum = vv[i] * fabs(sum)) >= big ) {
                big = dum;
                imax = i;
            }
        }
        if ( j != imax ) {
            for ( int k = 0; k < n; k++ ) {
                dum = a[imax][k];
                a[imax][k] = a[j][k];
                a[j][k] = dum;
            }
            *d = -(*d);
            vv[imax] = vv[j];
        }
        indx[j] = imax;
        if ( a[j][j] == 0.0 ) {
            a[j][j] = TINY;
        }
        if ( j != n ) {
            dum = 1.0 / (a[j][j]);
            for ( int i = j + 1; i < n; i++) {
                a[i][j] *= dum;
            }
        }
    }
    G_free_vector(vv);
    return 1;
}

#undef TINY

static void G_lubksb( double **a, int n, int *indx, double b[]) {
    int ii = -1, ip;
    double sum = 0.0;

    for ( int i = 0; i < n; i++ ) {
        ip = indx[i];
        sum = b[ip];
        b[ip] = b[i];
        if (ii >= 0) {
            for ( int j = ii; j < i; j++ ) {
                sum -= a[i][j]*b[j];
            }
        }
        else if ( sum > 0.0 ) {
            ii = i;
        }
        b[i] = sum;
    }
    for ( int i = n-1; i >= 0; i-- ) {
        sum = b[i];
        for ( int j = i+1; j < n; j++) {
            sum -= a[i][j] * b[j];
        }
        b[i] = sum / a[i][i];
    }
}
