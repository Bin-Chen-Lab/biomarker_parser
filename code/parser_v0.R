setwd("~/Documents/stanford/grant/2019/ot2/work/")
#parse excel and map to 
library("readxl")
library("stringr")
library("rpubchem")
library(httr)
require("jsonlite")

get_drugbank_id <- function(drug, drugbank_dic){
  return(drugbank_dic$id[drugbank_dic$name == drug][1])
}

get_pubchem_cid <- function(drug){
  drug = str_replace_all(drug, " ", "%20")
  url = paste0("https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/name/", drug, "/cids/txt?name_type=word")
  response = GET(url)
  if (status_code(response) == 200){
    cids = unlist(strsplit((content(response, as = "text", encoding = "UTF-8")), "\n"))
  }else{
    cids = NA
  }
  return(cids)
}

get_disease_id <- function(disease){
  disease = str_replace_all(disease, " ", "%20")
  
  base = "https://platform-api.opentargets.io/v3/platform/"
  endpoint = "public/search"
  url = paste(base,endpoint,"?","q","=", disease,"&filter=disease", sep="")
  response = GET(url)
  if (status_code(response) == 200){
    return_dz = content(response)$data
    if (length(return_dz) > 0){
      match_score = return_dz[[1]]$score
      match_type = return_dz[[1]]$type
      match_id = return_dz[[1]]$id
      if (match_score > 10){
        return (list(match_id, match_type, match_score))
      }
    }
  }
  
  return(list(NA, NA, NA))
  
}

#the matching is not accurate, e.g., KI-67
get_target_id <- function(target){
  target = str_replace_all(target, " ", "%20")
  
  base = "https://platform-api.opentargets.io/v3/platform/"
  endpoint = "public/search"
  url = paste(base,endpoint,"?","q","=", target,"&filter=target", sep="")
  response = GET(url)
  if (status_code(response) == 200){
    return_target = content(response)$data
    if (length(return_target) > 0){
      match_score = return_target[[1]]$score
      match_type = return_target[[1]]$type
      match_id = return_target[[1]]$id
      if (match_score > 100){
        return (list(match_id, match_type, match_score))
      }
    }
  }
   
  return(list(NA, NA, NA))
  
}

###
#prepare drugbank table
'drugbank = read.csv("drugbank vocabulary.csv", stringsAsFactors = F) #download from drugbank
drugbank_synonyms = unique(c(toupper(unlist(strsplit(paste(drugbank$Synonyms, collapse = " | ") , " | "))), toupper(drugbank$Common.name)))

drugbank_reformat = data.frame()
for (i in 1:nrow(drugbank)){
  fields = unique(toupper(c(drugbank$Common.name[i], unlist(strsplit(drugbank$Synonyms[i], " \\| ")))))
  drugbank_reformat = rbind(drugbank_reformat, data.frame(id = drugbank$DrugBank.ID[i], name = fields))
}
write.csv(drugbank_reformat, "drugbank_dic.csv")'
############
drugbank_dic = read.csv("drugbank_dic.csv", stringsAsFactors = F)

breast_cancer_trials =  data.frame(read_excel("Breast Cancer (LT NCT04001621, 1-50).xlsx", sheet = 1))
output_file = "Breast_Cancer_NCT04001621.csv"
for (i in 1:nrow(breast_cancer_trials)){
  print(i)
  drugs = toupper(unique(str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Drug[i]), collapse = ","), ",|，")), side = "both")))
  drugs_drugbank = paste(sapply(drugs, function(x) get_drugbank_id(x, drugbank_dic)), collapse = ",")
  drugs_pubchem = paste(sapply(drugs, function(x) get_pubchem_cid(x)[1]), collapse = ", ")

  biomarkers = toupper(unique(str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Enrichment.biomarker[i]), collapse = ","), ",|，")), side = "both")))
  biomarkers_ensembl = paste(sapply(biomarkers, function(x) get_target_id(x)[1]), collapse = ", ")
  
  diseases = toupper(str_trim(as.character(breast_cancer_trials$Disease[i]), side = "both"))
  diseases_EFO_MONDO = paste(sapply(diseases, function(x) get_disease_id(x)[1]), collapse = ", ")
  
  breast_cancer_trials$drug_drugbank_standard[i] = drugs_drugbank
  breast_cancer_trials$drug_pubchem[i] = drugs_pubchem
  breast_cancer_trials$biomarker_ensembl_standard[i] = biomarkers_ensembl
  breast_cancer_trials$diseases_EFO_MONDO_standard[i] = diseases_EFO_MONDO
  
  biomarker_direction = toupper((str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Biomarker.relationship[i]), collapse = ","), ",|，")), side = "both")))
  biomarker_type = toupper((str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Marker.type[i]), collapse = ","), ",|，")), side = "both")))
  biomarker_relation = toupper((str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Biomarker.logical.conditions[i]), collapse = ","), ",|，")), side = "both")))
  
  if (length(biomarker_direction) != length(biomarker_type) | length(biomarker_direction) != length(biomarkers) | length(biomarkers) != (length(biomarker_relation) + 1)){
    term = "failed"
  }else{
    term = ""
    for (k in 1:length(biomarkers)){
      if (k == length(biomarkers)){
        term = paste(term, paste(biomarkers[k], biomarker_type[k], biomarker_direction[k]))
      }else{              
        term = paste(term, paste(biomarkers[k], biomarker_type[k], biomarker_direction[k], biomarker_relation[k]))
      }
    }
  }
  
  breast_cancer_trials$biomarker_term[i] = str_trim(term)
}

write.csv(breast_cancer_trials, output_file)



biomarkers_matched2alias  = biomarkers[biomarkers %in% unlist(strsplit(paste(hgnc$alias_symbol, collapse = "|"), "\\|"))]


breast_cancer_trials =  data.frame(read_excel("Breast_cancer_CLINICALTRIAL_v7.xlsx", sheet = 1))

####
#biomarker mapping
biomarkers = toupper(unique(str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Enrichment.biomarker), collapse = ", "), ",")), " ")))

#HGNC
hgnc = read.csv("hgnc_complete_set.txt", sep = "\t", stringsAsFactors = F) #download from hgnc

biomarkers_matched = biomarkers[biomarkers %in% hgnc$symbol]
biomarkers_matched2alias  = biomarkers[biomarkers %in% unlist(strsplit(paste(hgnc$alias_symbol, collapse = "|"), "\\|"))]

biomarkers_failed = biomarkers[!biomarkers %in% c(biomarkers_matched, biomarkers_matched2alias)]

biomarkers_failed_id = sapply(biomarkers_failed, function(x){
  print(x)
  id = get_target_id(x)[1]
})

####
#
drugs = toupper(unique(str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Drug), collapse = ", "), ",")), side = "both")))

#drugbank
drugbank = read.csv("drugbank vocabulary.csv") #download from drugbank
drugbank_synonyms = unique(c(toupper(unlist(strsplit(paste(drugbank$Synonyms, collapse = " | ") , " | "))), toupper(drugbank$Common.name)))

drugs_matched = drugs[drugs %in% drugbank_synonyms]
drugs_failed = drugs[!drugs %in% drugs_matched]

drugs_cid = sapply(drugs[!drugs %in% drugs_matched], function(drug)
{ 
  cids = get_drug_cid(drug)
  cids[1]
})


##
#disease
diseases = toupper(unique(str_trim(unlist(strsplit(paste(as.character(breast_cancer_trials$Disease), collapse = ", "), ",")), side = "both")))

get_disease_id(diseases[1])






