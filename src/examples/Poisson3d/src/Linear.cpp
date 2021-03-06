//This file was generated by Femshop.

/*
Linear term
*/
DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,Q1d,in,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,Q1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,Q1d,imV2,out);

for(unsigned int k=0;k<(eleOrder+1);k++){
    for(unsigned int j=0;j<(eleOrder+1);j++){
        for(unsigned int i=0;i<(eleOrder+1);i++){
            out[k*(eleOrder+1)*(eleOrder+1)+j*(eleOrder+1)+i]*=(Jx*Jy*Jz*W1d[i]*W1d[j]*W1d[k]);
        }
    }
}

DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,QT1d,out,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,QT1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,QT1d,imV2,out);

