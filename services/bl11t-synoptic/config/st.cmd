# basic IOC startup script to just load ioc.db
cd "/epics/ioc"

epicsEnvSet EPICS_TZ GMT0BST

dbLoadDatabase dbd/ioc.dbd
ioc_registerRecordDeviceDriver pdbbase

dbLoadRecords /epics/ioc/config/ioc.db
iocInit
